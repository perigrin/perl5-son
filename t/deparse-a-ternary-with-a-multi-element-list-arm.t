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

# AN ARM THAT CALLS OR ALLOCATES merges through a Phi, built as a branch so
# the call runs only in its arm. In LIST context the Phi is the arm's list.
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my @a = $c ? (k(), 4) : (); print scalar(@a), " @a\n" }},
    'a list arm with a call');
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my @a = $c ? (k(), 4) : (5, 6, 7); print "@a\n" }},
    'two list arms, one with a call');
# chalk's _extract_fields: an optional pair whose value is a method call.
round_trips(q{package N { sub new { bless { v => $_[1] }, $_[0] } sub value { $_[0]{v} } }
    sub f { my $n = shift; return { k => 1, (defined $n->value ? (value => "${\$n->value}") : ()) } }
    for my $v (7, undef) { my $h = f(N->new($v)); print join(",", map { "$_=$h->{$_}" } sort keys %$h), "\n" }},
    'an optional pair with a method call in a hash constructor');
round_trips(q{for my $c (1, 0) { my @a = $c ? (1, 2) : [3]; print scalar(@a), "\n" }},
    'a list arm beside an allocating arm, in list context');

# A COUNT OF THAT PHI is the number of elements in the chosen arm, not 1: the
# merged value is a list, and counting it as one scalar folded to a constant.
round_trips(q{for my $c (1, 0) { my $n = () = $c ? ([1], [2], [3]) : (); print "$n\n" }},
    'a counted list arm that allocates');
round_trips(q{sub k { print "k\n"; 3 } for my $c (1, 0) { my $n = () = $c ? (k(), 4) : (); print "$n\n" }},
    'a counted list arm that calls');
round_trips(q{sub k { 3 } for my $c (1, 0) { my $n = () = $c ? (k(), k()) : (k()); print "$n\n" }},
    'counted list arms that both call');
round_trips(q{for my $c (1, 0) { my $n = (() = $c ? ([1], 2) : ()) + 0; print "$n\n" }},
    'a counted list arm in arithmetic');
round_trips(q{for my $c (1, 0) { print((() = $c ? ([1], [2]) : ()) == 2 ? "two\n" : "not\n") }},
    'a counted list arm compared');
round_trips(q{for my $c (1, 0) { my $n = () = ($c ? (1, 2) : ()); my $m = () = ($c ? ([1], 2) : ()); print "$n $m\n" }},
    'a constant and an allocating list arm counted side by side');

# SCALAR CONTEXT keeps only the last value. Anything ahead of it ran for its
# effects, which are already on the memory chain; spelled again it is a
# "Useless use" warning, whatever kind of node it is.
for my $src (q{my @x = (1, 2, 3); for my $c (1, 0) { my $n = $c ? (@x, 9) : 1; print "$n\n" }},
             q{my $i = 0; for my $c (1, 0) { my $x = $c ? ($i++, 7) : 8; print "$x $i\n" }},
             q{my $i = 0; for my $c (1, 0) { my $x = $c ? ($i++, $i++, $i) : 8; print "$x $i\n" }},
             q{sub k { print "k\n"; 3 } for my $c (1, 0) { my $x = $c ? (k(), 7) : 8; print "$x\n" }}) {
    round_trips($src, "scalar context: $src");
    emits_quietly($src, "scalar context: $src");
}

# STILL REFUSED: in the CALLER'S context the merged list would be read as a
# count by a scalar caller, where perl's comma yields the last element.
refuses(q{sub f { wantarray ? (7, 8) : [] } my @a = f(); print "@a\n";},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a list arm beside an allocating arm, in the caller\'s context');
refuses(q{my @a = (0); for my $c (1, 0) { my @r = ($c ? (($a[0] = 1), 2) : 3); print "@r @a\n" }},
    qr/GAP: a ternary with a multi-element list arm not yet lowered/,
    'a list arm that stores an element');

done_testing;
