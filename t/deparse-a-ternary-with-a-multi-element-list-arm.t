# ABOUTME: A ternary whose arm is a list of several values -- `$c ? (k => $v) : ()`,
# ABOUTME: `qw(A B)` -- picks between whole lists, and round trips in list and scalar context.

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

sub emits_quietly ($src, $name) {
    my $out = SoN::Deparse->new->render(graph_of($src) // {}) // return fail "$name: renders";
    my $f = "$dir/q." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $out; close $fh;
    my $err = qx(/usr/bin/timeout 10 $^X $f 2>&1 >/dev/null); unlink $f;
    is $err, '', "$name: the emission warns nothing";
}

sub refuses ($src, $why, $name) {
    graph_of($src);
    like producer_stderr(), $why, "$name: refuses by its cause";
}

# EACH ARM IS ITS WHOLE LIST. The arm pushes every value it builds, so the
# select is between two lists, not between the last value of each.
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2) : (3, 4); print "@a\n" }},
    'two lists of two');
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2, 3) : (4); print scalar(@a), " @a\n" }},
    'lists of different lengths');

# chalk's optional-key idiom (TypeInferenceActions, _replay_classes).
round_trips(q{sub f { my $n = shift; return { a => 1, (defined $n ? (name => $n) : ()) } }
    print join(",", sort %{f("z")}), "|", join(",", %{f()}), "\n";},
    'an optional pair in a hash constructor');

# chalk's _emit_read_slot_as: one arm a deref, the other a qw list.
round_trips(q{for my $r ([qw(X Y Z)], undef) { my %o = (r => $r);
    my @t = $o{r} ? $o{r}->@* : qw(Int Num); print "@t\n" }},
    'a deref against a qw list');

round_trips(q{for my $c (1, 0) { print $c ? ("a", "b") : "c"; print "\n" }},
    'a list arm printed');
round_trips(q{for my $c (1, 0) { my @a = (0, ($c ? (1, 2) : ()), 9); print scalar(@a), " @a\n" }},
    'nested in an outer list');

# THE CALLER'S CONTEXT. A sub's last statement carries no want flag; in
# scalar context perl's comma yields the last element, in list context all.
round_trips(q{sub g { $_[0] ? (1, 2) : ("s") } my $s = g(1); my @l = g(1); my $t = g(0);
    print "$s ", scalar(@l), " $t\n";},
    'a list arm as a sub value, scalar and list callers');

round_trips(q{sub f { wantarray ? (1, 2) : "s" } my @l = f(); my $s = f(); print scalar(@l), " $s\n";},
    'the wantarray idiom');

# SCALAR CONTEXT yields the last element, and the emission says so quietly:
# a constant ahead of it is a "Useless use of a constant" warning.
round_trips(q{my ($a, $b) = (5, 6); for my $c (1, 0) { my $x = $c ? ($a, $b) : 3; print "$x\n" }},
    'a list arm in scalar context');
emits_quietly(q{my ($a, $b) = (5, 6); for my $c (1, 0) { my $x = $c ? ($a, $b) : 3; print "$x\n" }},
    'a list arm in scalar context');

# A COUNT OF THE LIST is the number of elements, not the last one.
round_trips(q{for my $c (1, 0) { my $n = () = ($c ? (7, 8, 9) : ()); print "$n\n" }},
    'counted through an empty list assign');

# STILL REFUSED: the merge through a Phi spells one value per arm.
refuses(q{sub f { wantarray ? (7, 8) : [] } my @a = f(); print "@a\n";},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a list arm beside an allocating arm');

done_testing;
