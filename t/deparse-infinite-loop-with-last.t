# ABOUTME: `while (1) { ...; last if C }` is a Loop with no Projs and the exit inside.
# ABOUTME: The If hanging off the Loop is the test; index 0 leaves, index 1 iterates.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/r." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $out = qx(timeout 10 $^X $f 2>&1); unlink $f; return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f; return eval { JSON::PP->new->decode($j) };
}

sub round_trips ($src, $name) {
    my $want = run_perl($src);
    my $data = graph_of($src);
    unless ($data && $data->{methods}{'main::__PROGRAM__'}) {
        fail "$name: translates"; return;
    }
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

# A LOOP WITH NO PROJS IS `while (1)`. There is no header condition to test,
# so the producer emits no arms -- measured on
# `my $x=0; while (1) { $x = $x+1; last if $x == 3 }`:
#
#      4 Loop  in=[0]      ci=0        NO Projs
#      5 Phi   in=[3, 7]   region=4    the induction
#     14 If    in=[4, 13]  ci=4        the exit test, hanging off the Loop
#     15 Proj  in=[14] index=0         LEAVES, to the continuation
#     19 Proj  in=[14] index=1         ITERATES
#
# so the exit lives inside the body, and the If's index-0 arm is what follows
# the loop rather than an arm of a branch within it.
#
# THE ITERATION COUNT IS THE CHECK. A loop that exits one iteration early or
# late still prints a number, so every case below reports the counter.
subtest 'while (1) with last' => sub {
    round_trips(<<'SRC', 'exit after three iterations');
my $x = 0;
while (1) {
    $x = $x + 1;
    last if $x == 3;
}
print "x=$x\n";
SRC

    round_trips(<<'SRC', 'exit on the first iteration');
my $x = 0;
while (1) {
    $x = $x + 1;
    last if $x == 1;
}
print "x=$x\n";
SRC
};

# WORK AFTER THE `last` MUST NOT RUN on the iteration that exits -- that is
# the difference between a `last` and a bottom-tested condition.
subtest 'statements after the last' => sub {
    round_trips(<<'SRC', 'the tail is skipped on the exiting pass');
my $x = 0;
my $tail = 0;
while (1) {
    $x = $x + 1;
    last if $x == 3;
    $tail = $tail + 1;
}
print "x=$x tail=$tail\n";
SRC
};

# THE EXIT IS NOT ALWAYS THE FIRST NODE. A body that does work before testing
# puts that work between the Loop and the If -- measured on base/while.t,
# `Loop(31)` is followed by `EntryWrite(32)` and only then the exit If. Keying
# on "the If pinned directly on the Loop" found nothing there and refused.
subtest 'work before the exit test' => sub {
    round_trips(<<'SRC', 'a package write, then the last');
$main::x = 0;
while (1) {
    $main::x = $main::x + 1;
    last if $main::x == 3;
}
print "x=$main::x\n";
SRC
};

# A HEADER-TESTED LOOP MUST NOT REGRESS -- it has two Projs and is the common
# case the diamond logic was written for.
subtest 'a header-tested while still round-trips' => sub {
    round_trips(<<'SRC', 'a counted while');
my $x = 0;
while ($x != 3) { $x = $x + 1 }
print "x=$x\n";
SRC
};

done_testing;
