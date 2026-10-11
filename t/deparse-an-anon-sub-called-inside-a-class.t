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
# A CLOSURE OVER A FIELD refuses: lifted out of its method, the field names
# nothing (a stray file lexical gave `00` for perl's `10`).
graph_of(q{use v5.38; use experimental "class"; class C { field %m; method n { $m{a} = 1; my $in = sub ($k) { exists $m{$k} ? 1 : 0 }; return $in->("a") . $in->("b") } } print C->new->n, "\n";});
like producer_stderr(), qr/anonymous sub closing over the field %m is not yet lowered/,
    'a closure over a field refuses, as chalk IR::Graph::nodes does';
round_trips(q{package P; sub run { my $f = sub { $_[0] + 1 }; $f->(1) } package main; print P::run(), "\n";},
    'a closure called inside a package sub');
round_trips(q{sub f { my $g = sub { 5 }; $g->() } print f(), "\n";},
    'a closure called inside a main sub');

done_testing;
