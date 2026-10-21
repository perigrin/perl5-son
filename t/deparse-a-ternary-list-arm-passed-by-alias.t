# ABOUTME: A ternary list arm handed to an alias -- a foreach, a grep or map, a call --
# ABOUTME: is a list slice of the ternary, which yields the elements themselves.

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


sub refuses ($src, $cause, $name) {
    graph_of($src);
    like producer_stderr(), $cause, "$name: refused, naming its cause";
}

# Either the emission matches perl, or the deparser refuses naming $cause.
sub round_trips_or_refuses ($src, $cause, $name) {
    my $d = SoN::Deparse->new;
    my $out = $d->render(graph_of($src) // {});
    return like $d->gap // q{}, $cause, "$name: refused, naming its cause"
        unless defined $out;
    my $got = run_perl($out);
    is $got, run_perl($src), $name
        or diag "--- emitted ---\n$out";
}
# `COND ? @$x : ()` HANDED TO AN ALIAS was refused: merged as a copy, a
# write through the alias would miss the array. Spelled as a list slice of
# the ternary it is no copy -- perl's list slice yields the elements -- and
# a store through it still refuses (no container to name).
my $ALIAS = qr/GAP: a ternary list arm passed by alias/;
round_trips(q{sub f { my ($x, $c) = @_; my $s = ""; for my $e ($c ? @$x : ()) { $s .= $e } return $s } print f([1,2], 1), f([3], 0), "\n";},
    'a foreach over a ternary list arm');
round_trips(q{sub f { my ($x, $c) = @_; return join ",", grep { $_ > 1 } ($c ? @$x : ()) } print f([1,2,3], 1), "|", f([3], 0), "\n";},
    'a grep over a ternary list arm');
round_trips(q{sub g { $_[0] = 9; scalar @_ } sub f { my ($x, $c) = @_; my $n = g($c ? @$x : ()); return "$n@$x" } print f([1,2], 1), f([3], 0), "\n";},
    'a call argument that is a ternary list arm, written by the callee');
round_trips(q{sub b { $_ .= "!" } sub f { my ($x, $c) = @_; for ($c ? @$x : ()) { b() } return "@$x" } print f([1,2], 1), f([3], 0), "\n";},
    'a callee writing the topic over a ternary list arm');
round_trips(q{sub ok1 { $_ > 1 } sub f { my ($x, $c) = @_; return join ",", map { $_ * 2 } grep { ok1() } ($c ? @$x : ()) } print f([1,2,3], 1), "|", f([3], 0), "\n";},
    'a callee reading the topic of a grep over a ternary list arm');
round_trips_or_refuses(q{sub f { my ($x, $c) = @_; for my $e ($c ? @$x : ()) { $e .= "!" } return "@$x" } print f([1,2], 1), f([3], 0), "\n";},
    qr/GAP: an element store into an anonymous container/, 'an iterator write over a ternary list arm');
# READ EARLIER TOO, the dereference was snapshotted ahead of the call as
# if the arm list copied it, and the callee's write missed the array.
round_trips(q{sub g { $_[0] = 9; scalar @_ } sub f { my ($x, $c) = @_; my $s = join "", @$x; my $n = g($c ? @$x : ()); return "$s|$n|@$x" } print f([1,2], 1), " ", f([3], 0), "\n";},
    'a call over a ternary list arm of a dereference read before it');
for ( [ 'a topic write',             q{$_ .= "!" for ($c ? @$x : ());} ],
      [ 'a map block writing its topic', q{my @r = map { $_ .= "!"; 1 } ($c ? @$x : ());} ] ) {
    round_trips_or_refuses(qq{sub f { my (\$x, \$c) = \@_; $_->[1] return "\@\$x" } print f([1,2], 1), f([3], 0), "\\n";},
        qr/GAP: an element (?:store into an anonymous container|of a `TernaryExpr`)/, "$_->[0] over a ternary list arm");
}
round_trips_or_refuses(q{sub f { my ($x, $y, $c) = @_; for ($c ? ($x, $y) : ()) { $_ = 5 } return "$x$y" } print f(1, 2, 1), f(3, 4, 0), "\n";},
    qr/GAP: an element store into an anonymous container/, 'a topic write over a ternary arm of scalars');
# A REFERENCE TO IT is one to the array, `\@$x`, not to each element: perl
# dies "Not a SCALAR reference" where a list of copies printed `9`.
refuses(q{sub f { my ($x, $c) = @_; my @r = \($c ? @$x : ()); ${$r[0]} = 9 if @r; return "@$x" } print eval { f([1,2], 1) } // "died", "\n";},
    $ALIAS, 'a reference to a ternary list arm');

done_testing;
