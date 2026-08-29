# ABOUTME: A Phi identity check compares node IDs, which are STRINGS, not numbers.
# ABOUTME: Numeric == numifies every id to 0 and matches any pair of nodes.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub nodes_by_op ($graph, $op) {
    return grep { $_->operation eq $op } $graph->nodes->@*;
}

# NODE IDS ARE STRINGS, and every one of them numifies to 0:
#
#   Phi#unique4
#   Phi#unique5
#   Subscript|ArrayRef#2|Phi#unique4|MemStart
#   Constant|const_type=integer|value=1
#
# So `$a->id == $b->id` is TRUE for any pair. Two DIFFERENT Phis in one loop --
# the index and the accumulator -- compare equal, and so does a Phi against a
# Constant. This test pins the property that makes such a comparison unsound,
# so that a numeric identity check cannot be reintroduced without a red test.
subtest 'node ids are strings and do not survive numeric comparison' => sub {
    my $g = translate('sub { my @a=(1,2,3); my $s=0; for my $x (@a) { $s = $s + $x } $s }');
    my @phis = nodes_by_op($g, 'Phi');
    ok(scalar @phis >= 2, 'the loop has at least two Phis (index and accumulator)')
        or return;

    isnt($phis[0]->id, $phis[1]->id, 'the two Phis are DIFFERENT nodes');

    my $numeric_match = do { no warnings 'numeric'; $phis[0]->id == $phis[1]->id };
    ok($numeric_match,
        'and numeric == wrongly reports them EQUAL -- ids numify to 0');

    ok(($phis[0]->id ne $phis[1]->id),
        'string ne is the comparison that actually distinguishes them');
};

# THE CONSEQUENCE. _backedge_is_phi_recurrence guards the ONE branch of
# _patch_loop_phi that keeps a Phi's init stamp when the back-edge is unstamped.
# Its contract (its own comment): "A back-edge that is NOT arithmetic over $phi,
# or whose unstamped input is not an element read, is a genuine unknown and
# still GAPs."
#
# With numeric ids that predicate cannot say no:
#   :3085  grep { $_->id == $phi->id } @ins   -- matches ANY input, so the
#          "consumes the Phi directly" guard never rejects;
#   :3090  next if $in->id == $phi->id        -- skips EVERY input, so the
#          "unstamped input must be a Subscript" check never runs at all.
#
# The function therefore returns true for any arithmetic back-edge, and the
# `die "GAP: loop-carried value loses its stamp"` below it is unreachable
# through this path. A Phi then keeps an init stamp it has not earned -- the
# same unverified-provenance shape as the fabricated-Num miscompile (gate
# 215 -> 199), where a type-SOUND stamp was still a WRONG stamp.
subtest 'the recurrence predicate can still say no' => sub {
    my $g = translate('sub { my @a=(1,2,3); my $s=0; for my $x (@a) { $s = $s + $x } $s }');
    my @phis = nodes_by_op($g, 'Phi');
    ok(scalar @phis >= 2, 'two Phis to cross-check') or return;

    # An Add that reads phi[0] must NOT be reported as a recurrence over
    # phi[1]. Under numeric ids it is, because every id compares equal.
    my ($add) = grep {
        my $n = $_;
        grep { $_->id eq $phis[0]->id } $n->inputs->@*;
    } nodes_by_op($g, 'Add');
    ok($add, 'an Add reading the first Phi exists') or return;

    my $reads_other = grep { $_->id eq $phis[1]->id } $add->inputs->@*;
    ok(!$reads_other, 'that Add does NOT read the second Phi (string comparison)');

    my $numeric_reads_other = do {
        no warnings 'numeric';
        scalar grep { $_->id == $phis[1]->id } $add->inputs->@*;
    };
    ok($numeric_reads_other,
        'but numeric == claims it does -- the guard cannot reject');
};

done_testing;
