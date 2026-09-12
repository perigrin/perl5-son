# ABOUTME: The first differential-oracle gate -- base/if.t must round-trip through SoN::Deparse.
# ABOUTME: Observational equivalence: run the original and the emitted program, compare output.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

use SoN::Deparse;

# THE ORACLE. Every correctness check on the producer today is structural --
# read the graph, reason about whether it says what perl says. Every defect
# found this way was a WRONG ANSWER from a structurally plausible graph, and
# the suite was green throughout (see
# docs/plans/2026-09-12-deparse-target-as-a-differential-oracle.md).
#
# This runs the original under perl, renders the graph back to Perl, runs that,
# and compares. The criterion is OBSERVATIONAL EQUIVALENCE: same output, same
# effects, same order where order is observable. The emitted program may differ
# from the input in the unordered parts -- it is allowed to be ugly, not wrong.
#
# base/if.t is the first target: 9 lines, deterministic 3-line output, no named
# subs, and a node vocabulary that is exactly the Phase 1 core -- a package
# scalar write, reads that must observe it, an If/Proj/Region diamond taken
# both ways, and Print so there is output to diff.

my $SRC = <<'PERL';
print "1..2\n";
$x = 'test';
if ($x eq $x) { print "ok 1 - if eq\n"; } else { print "not ok 1 - if eq\n";}
if ($x ne $x) { print "not ok 2 - if ne\n"; } else { print "ok 2 - if ne\n";}
PERL

my $dir = tempdir(CLEANUP => 1);

sub run_perl ($src) {
    my $f = "$dir/run.$$." . int(rand 1e6) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $out = qx($^X $f 2>&1);
    unlink $f;
    return $out;
}

sub graph_of ($src) {
    my $f = "$dir/g.$$." . int(rand 1e6) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $json = qx($^X -Ilib -MO=SoN,json,package=main $f 2>/dev/null);
    unlink $f;
    return eval { JSON::PP->new->decode($json) };
}

subtest 'base/if.t round-trips to observationally equivalent output' => sub {
    my $expected = run_perl($SRC);
    is $expected, "1..2\nok 1 - if eq\nok 2 - if ne\n",
        'the original behaves as expected' or return;

    my $data = graph_of($SRC);
    ok $data && $data->{methods}{'main::__PROGRAM__'},
        'it translates to a graph' or return;

    my $emitted = SoN::Deparse->new->render($data);
    ok defined $emitted && length $emitted, 'the graph renders to Perl source'
        or return;

    # THE ASSERTION THAT MATTERS. Not "does it look right" -- run it.
    my $got = run_perl($emitted);
    is $got, $expected, 'the emitted program behaves identically'
        or diag "--- emitted ---\n$emitted--- got ---\n$got--- want ---\n$expected";
};

done_testing;
