#!/usr/bin/env perl
# ABOUTME: A merge whose arm is itself a merge must still record its predecessors.
# ABOUTME: Without them the consumer searches, and for nested branches it guesses wrong.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# A Phi records `predecessors` -- which Proj each incoming value arrives from --
# so the backend reads arm identity instead of searching for it. StackSim::merge
# supplies them only when BOTH arms resolve to a Proj, deliberately: the consumer
# pairs by position, so a partial list would silently mis-pair.
#
# _arm_proj walks an arm's control chain back to its Proj and STOPS at a Region,
# because descending past another merge would attribute this slot to the wrong
# branch. Correct for a flat branch. But for a NESTED branch the outer merge's
# arm IS the inner Region, so the walk stops immediately, returns undef, and the
# all-or-nothing guard drops predecessors for the OUTER Phi entirely.
#
# Measured (2026-08-20) on
#   my @a=(1,2,3); my $x=1; my $y=1; my $n=0;
#   if ($x) { if ($y) { $a[0]=9; $n=1 } else { $a[0]=8; $n=2 } }
# the inner Phis carry predecessors and the outer ones do not, so the backend
# falls back to the Region search -- which pairs them backwards and emits
#   %tmp_39 = phi i64 [ %tmp_22, %if.merge.6 ], [ %tmp_38, %if.else.2 ]
# naming %tmp_38 (defined IN if.merge.6) as arriving from if.else.2. lli rejects
# it: "Instruction does not dominate all uses!". Invalid IR rather than a wrong
# answer, but only because LLVM's verifier caught what nothing here did.
#
# A nested Region's identity IS reachable: Region.head is the inner If, whose
# control_in is the outer Proj. That is the arm this merge came from.
# ---------------------------------------------------------------------------

sub nested_graph () {
    my $sub = eval q{
        sub {
            my @a = (1,2,3);
            my $x = 1; my $y = 1; my $n = 0;
            if ($x) { if ($y) { $a[0]=9; $n=1 } else { $a[0]=8; $n=2 } }
            $n;
        }
    };
    die "probe sub failed to compile: $@" unless $sub;
    return SoN::FromOptree->translate($sub);
}

subtest 'every merge Phi in a nested branch records its predecessors' => sub {
    my $g = eval { nested_graph() };
    ok(defined $g, 'the nested probe translated') or do { diag($@); return };

    my @phis = grep {
        ref($_) && $_->can('operation') && $_->operation eq 'Phi'
    } $g->nodes->@*;

    ok(scalar(@phis) >= 2, 'the nested branch built more than one Phi')
        or diag('phi count: ' . scalar(@phis));

    # A LOOP Phi is exempt (its values pair with entry/back edges, not merge
    # arms); there are none here, so every Phi found is a merge Phi.
    my @without = grep { !defined $_->predecessors } @phis;

    is(scalar(@without), 0,
       'no merge Phi is missing predecessors -- the OUTER merge, whose arm is '
     . 'the inner Region, is the one that used to be')
        or diag('missing on: ' . join(', ', map { 'Phi#' . $_->id } @without));
};

subtest 'a recorded predecessor is always a Proj' => sub {
    # The guard that keeps this honest: recording SOMETHING is not the goal,
    # recording the right kind of thing is. If a fix ever supplies the Region
    # itself (or the inner If) as an arm, the consumer would pair against a node
    # that is not a branch edge at all.
    my $g = eval { nested_graph() };
    ok(defined $g, 'the nested probe translated') or do { diag($@); return };

    my @bad;
    for my $p (grep { ref($_) && $_->can('operation') && $_->operation eq 'Phi' }
               $g->nodes->@*) {
        my $preds = $p->predecessors // next;
        for my $q ($preds->@*) {
            push @bad, 'Phi#' . $p->id . ' -> ' .
                (ref($q) && $q->can('operation') ? $q->operation : 'undef')
                unless ref($q) && $q->can('operation') && $q->operation eq 'Proj';
        }
    }
    is(scalar(@bad), 0, 'every recorded predecessor is a Proj')
        or diag(join('; ', @bad));
};

done_testing;
