# A loop-carried stamp needs no seeding, and seeding would be unsound

**Date:** 2026-09-12
**Status:** Analysis. The gate fix it justifies is in `_patch_loop_phi`.

## What was refused

    GAP: loop-carried value loses its stamp (unstamped back-edge);
         fixpoint restamping not yet lowered

Three corpus files were behind it: `comp/proto.t`, `comp/require.t`,
`comp/retainedlines.t`.

## The refusal fired on a guard that is always true

`_patch_loop_phi` has two branches. The first was corrected at some point to
ask `_is_narrowed`; the second still asked `defined $phi->stamp` -- and EVERY
Value node carries a stamp now, so it was unconditionally true. The trap is
named in this same sub's own comment, twenty lines above:

> "Has a stamp" is not the question -- every Value node carries one now. The
> question is whether it says anything, and `Unknown` is how a stamp says it
> does not.

## Why falling through is sound

`_make_loop_phi` stamps a loop Phi ONLY when its init arm is narrowed:

    (_is_narrowed($init->stamp) ? (stamp => $init->stamp) : ())

So an `Unknown` Phi provably never asserted anything. The refusal's stated
rationale -- "the body was already stamped against this Phi's optimistic init
stamp, so un-stamping leaves stale stamps contaminating sibling Phi joins" --
describes a contamination that cannot exist when no claim was ever made. The
body was walked against `Unknown` and no consumer holds a narrower claim this
back-edge could contradict.

Measured: all three corpus files reach the refusal with `phi=Unknown` AND BOTH
ARMS `Unknown`, so `join(Unknown, Unknown)` is `Unknown` -- there is no
widening either, and nothing to restamp.

## The widening case was already handled

Worth recording because it is the case a "fixpoint" would be built for, and it
does not need one:

    sub f { my $t = 0; for my $i (1,2) { $t = $t . "x" } return $t }
      Phi:Str  in=[Constant:Int, Concat:Str]

Both arms narrowed, so the FIRST branch joins them and the Phi comes out `Str`.
The walker gets this right today.

## Why seeding `_stamp_merges` from the init arm is the wrong fix

`_stamp_merges` requires EVERY input narrowed, which a recurrence never
satisfies: `Phi(init, Add(Phi, ...))` -- the Phi waits on the back-edge and the
back-edge waits on the Phi. The textbook move is to seed from the init arm and
iterate to a fixpoint.

IT IS UNSOUND HERE, for two compounding reasons.

1. **The write-once invariant forbids the re-join.** The 18 `eq 'Unknown'`
   guards are a monotonicity/termination guard: a stamp is written once, from
   Unknown, after all requirements accumulate, so a join only ever moves up a
   finite-height lattice. A seeded Phi is no longer Unknown, so every later
   pass SKIPS it -- the seed freezes, and nothing corrects it if the back-edge
   later narrows to something wider.

2. **The remaining cycles would not resolve anyway.** Of the 12 unstamped Phis
   with exactly one narrowed arm, NINE have the other arm as another unstamped
   `Phi` or a `PadAccess`:

       4  narrowed=Scalar (Subscript)  other=Phi
       4  narrowed=Int    (Subscript)  other=Phi
       1  narrowed=Undef  (Constant)   other=Call
       1  narrowed=Num    (Add)        other=TernaryExpr
       1  narrowed=Int    (Call)       other=PadAccess
       1  narrowed=Num    (Assign)     other=Phi

   Seeding would propagate a guess along a chain of Phis, each frozen by the
   guard, with no re-join. That is the "unstamp to trigger recomputation"
   design in a more elaborate costume.

`PadAccess` being open is DELIBERATE, not a hole to fill: `_make_pad_access`
leaves it Unknown so backward inference can meet the declared slot type with
the use-site requirement (`meet(Scalar, Num) = Num`). Stamping it at
construction was tried and came out strictly wider -- it broke
t/wire-backward-inference.t.

## What stays refused

A STAMPED Phi over an unstamped back-edge, which is a genuinely different case:
the init DID assert a type, the body was walked against it, and the back-edge
cannot confirm it.

    sub f { my ($n)=@_; my $t=0; for my $i (1,2) { $t += $n } return $t }
      init=Constant/Int  phi=Int  post=Add/Unknown

That refusal is unchanged and has a test. Closing it needs the real fixpoint --
and the real fixpoint needs a "not yet computed" state distinct from the
lattice, so a revision is not a second write. That is a change to the stamp
model, not to this sub.

Related: memory note `unknown-is-write-once-not-a-sentinel`.

## A pre-existing crash this UNCOVERED

With the gate fixed, `comp/require.t` reports

    INTERNAL ERROR translating main::dofile: Stack underflow at StackSim.pm:25

NOT caused by this change -- verified by stashing it: the same underflow is
present at baseline, masked in the survey's single-line report behind the stamp
GAP that fired first. An INTERNAL ERROR is the worse category (it fires before
any honest refusal could, and names StackSim rather than the unhandled op), so
it is recorded here rather than left to be rediscovered.

FIXED the same day, in the commit after this one: `$void_effect_call` meant
"void AND effectful" -- pin on control and push nothing, which coincide for a
genuinely void call -- and the global-state widening set that SAME flag for a
NON-void require/dofile to borrow the pinning, inheriting the value suppression.
So `require "x.pm" or die $@` pushed no LHS and the `or` handler's unconditional
pop underflowed. Two decisions, now two flags.
