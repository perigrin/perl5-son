# ABOUTME: A loop-Phi-indexed element read ($a[$i] in a loop body) GAPs cleanly
# ABOUTME: instead of crashing with an internal undef-deref / stack underflow.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `for my $i (0..2) { $s += $a[$i] }` reads an array element whose index is a
# loop-carried Phi. Building the Subscript during the body SCOUT died with
# "consumers on undefined value" (the scout StackSim had no memory, so the
# element read's memory input was undef) -- an INTERNAL error B::SoN silently
# masked as a dropped sub. The scout sims now carry a throwaway MemStart, so the
# element read builds; the case then reaches the loop-carried-stamp fixpoint GAP
# (a real unbuilt feature). The contract: a clean GAP, never a silent crash.

sub gap_message ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    my $translate_err = dies { SoN::FromOptree->translate($cv) };
    return $translate_err // '';
}

subtest 'a loop-Phi-indexed element read GAPs cleanly (no internal crash)' => sub {
    my $err = gap_message(
        'sub { my @a=(10,20,30); my $s=0; for my $i (0..2) { $s += $a[$i] } $s }');
    ok($err, 'the element-read-in-loop refuses (does not silently succeed-wrong)');
    like($err, qr/^GAP:/, 'the die is a clean GAP, not an internal error')
        or diag("actual: $err");
    unlike($err, qr/consumers|undefined value|Stack underflow/,
        'not an internal undef-deref / stack-underflow crash')
        or diag("actual: $err");
};

done_testing;
