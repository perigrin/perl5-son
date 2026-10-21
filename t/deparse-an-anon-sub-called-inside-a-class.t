# ABOUTME: A closure lifted to file scope is called by its main:: name from inside a
# ABOUTME: class or package, where a bare mangled name would resolve in that package.

use v5.42.0;
use Test2::V0;
use JSON::PP;
# ABOUTME: A whole-aggregate assignment in a branch arm, in a loop or straight-line, round
# ABOUTME: trips: each assigned version is its own variable and an array merge stays an array.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(/usr/bin/timeout 10 $^X $f 2>/dev/null); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub producer_stderr () {
    open my $fh, '<', "$dir/err" or return ''; local $/; return <$fh> =~ s/^\S+ syntax OK\n//mr;
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    my $err  = producer_stderr();
    is $err, '', "$name: the producer says nothing";
    if (!$data) { fail "$name: translates"; return }
    my $d = SoN::Deparse->new;
    my $out = $d->render($data);
    unless (defined $out) {
        my $g = $d->gap // '(no reason)'; $g =~ s/\n.*//s;
        fail "$name: renders"; diag $g; return;
    }
    my $got = run_perl($out);
    is $got, $want, $name
        or diag "--- emitted ---\n$out--- got ---\n$got--- want ---\n$want";
}


# The emission must also be QUIET: a second `my @e` in one scope is a "masks
# earlier declaration" warning, and the masked variable is the defect.
sub emits_quietly ($src, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}


round_trips(q{use v5.38; use experimental "class"; class C { method run { my $f = sub ($x) { $x * 2 }; return $f->(21) } } print C->new->run, "\n";},
    'a closure called inside a class method');
# A CLOSURE OVER A FIELD sees the instance its method runs on. Lifted out of
# the method the field named nothing (a stray file lexical gave `00` for
# perl's `10`), so it was refused -- and that held chalk's IR::Graph::nodes,
# which closes over its `field %cache`, out of the round trip. Two instances,
# so a closure reading the first one's field is caught.
round_trips(q{use v5.38; use experimental "class"; class C { field %m; method add ($k) { $m{$k} = 1 } method n { my $in = sub ($k) { exists $m{$k} ? 1 : 0 }; return $in->("a") . $in->("b") } } my ($x, $y); $x = C->new; $y = C->new; $x->add("a"); $y->add("b"); print $x->n, $y->n, $x->n, "\n";},
    'a closure over a hash field reads its own instance');
round_trips(q{use v5.38; use experimental "class"; class C { field $n = 0; method bump { my $inc = sub { $n = $n + 1 }; $inc->(); $inc->(); return $n } } my $x = C->new; my $y = C->new; print $x->bump, $y->bump, $x->bump, "\n";},
    'a closure that writes a scalar field writes its own instance');
round_trips(q{use v5.38; use experimental "class"; class C { field $n = 0; method bump { my $inc = sub { $n = $n + 1 }; my $r = $inc->(); return "$r$n" } } my $x = C->new; print $x->bump, $x->bump, "\n";},
    'a closure returns the value it stored into a field');
# A CLOSURE OVER ITS METHOD'S OWN PARAMETER. The capture was declared at
# file scope for the lifted body, and the signature declared its own: the
# body read the one nothing assigned. chalk's Context::leaves passes such a
# closure to walk_all, and its class filter let every node through.
round_trips(q{use v5.38; use experimental "class"; class C { method pick ($cls = undef) { my @r = grep { defined } map { $self->test($cls)->($_) } (1, 2, 3); return scalar @r } method test ($c) { return sub ($n) { !$c || $n == $c ? $n : undef } } method each_ ($want) { return $self->walk(sub ($n) { $n == $want ? $n : undef }) } method walk ($cb) { return join ",", grep { defined } map { $cb->($_) } (1, 2, 3) } } my $o = C->new; print $o->pick, $o->pick(2), " ", $o->each_(3), "\n";},
    'a closure over its method\'s own parameter');
round_trips(q{use v5.38; sub walk ($cb) { join ",", grep { defined } map { $cb->($_) } (1, 2, 3) } sub only ($want) { walk(sub ($n) { $n == $want ? $n : undef }) } print only(2), only(3), "\n";},
    'a closure over a sub\'s own parameter');
# A CLOSURE THAT OUTLIVES ITS METHOD keeps the instance it was made on, as
# perl's does: each call of the method makes its own.
round_trips(q{use v5.38; use experimental "class"; class C { field $v :param; method getter { return sub { $v } } } my $g = C->new(v => 1)->getter; my $h = C->new(v => 2)->getter; print $g->(), $h->(), $g->(), "\n";},
    'a closure over a field that escapes its method keeps its instance');
round_trips(q{package P; sub run { my $f = sub { $_[0] + 1 }; $f->(1) } package main; print P::run(), "\n";},
    'a closure called inside a package sub');
round_trips(q{sub f { my $g = sub { 5 }; $g->() } print f(), "\n";},
    'a closure called inside a main sub');

done_testing;
