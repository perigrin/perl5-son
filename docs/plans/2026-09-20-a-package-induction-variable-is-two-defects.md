# A C-style `for` over a package scalar is two defects, and the second blocks the first

perigrin asked why `loop-carried value loses its stamp` went from 1 to 2
occurrences during the loop work. It did not regress -- `cmd/subval.t` ADVANCED
past the bare-block `continue` refusal and now reaches this one. `cmd/for.t`
had it all along.

## Reproduced in one line

    for ($i = 0; $i <= 3; $i++) { print "i=$i\n" }

A C-style `for` whose induction variable is an UNDECLARED PACKAGE SCALAR.
This is cmd/for.t's FIRST loop (line 5), so the whole file stands behind it.

## Defect 1: the stamp is deferred, and the floor is knowable

Measured at the refusal, both corpus files hit the identical shape:

    Phi/Int   back-edge = Add(EntryDef/Unknown, Constant/Int)

The EntryDef is Unknown because a package scalar's stamp comes from B::SoN's
POST-PASS (`_floor_package_globals`), while `_patch_loop_phi` runs during the
walk. The same read outside a loop is stamped correctly:

    EntryDef 6  Int     the read after `$i = 0`

THE ANSWER THAT PASS WILL GIVE IS FIXED BY THE SIGIL: `$` floors to Scalar,
`@` to Array, `%` to Hash. So the join can be computed at walk time, and
`join(Int, Scalar)` is `Scalar` -- the Phi must WIDEN, taking the existing
widening path (`set_stamp` + `_restamp_cone`), not the recurrence escape
hatch. Keeping Int would be a NARROWER claim than the truth, which is exactly
the stale stamp the refusal exists to prevent.

Implemented as `_deferred_backedge_floor`, and it worked -- the producer
translated and terminated.

## Defect 2: the emitted loop never terminates

    $main::i = 0;
    my $phi22 = 0;
    my $inv10 = $main::i;          <- hoisted as loop-INVARIANT
    while (($inv10 <= 3)) {
      print ...;
      $main::i = ($main::i + 1);   <- and the body writes it
    }

`_loop_invariant_roots` asks "does this subtree contain a loop Phi". A package
variable never does: package variables carry their updates on the MEMORY
CHAIN, not in SSA. So a read the body WRITES looks invariant and is pinned to
its entry value, and the condition can never change.

This is a PRE-EXISTING deparser defect that defect 1 merely exposes -- nothing
reached this shape before, because the producer refused it.

## Reverted

Shipping defect 1 alone turns an honest refusal into an infinite loop, which
the contract ranks below the refusal. Reverted; the refusal stands.

## Remaining work

1. Teach `_loop_invariant_roots` that a package read is loop-varying when the
   body writes that variable. The memory chain is where that fact lives: a
   read whose memory input is (transitively) a write inside the loop is not
   invariant. A Phi test cannot see it.
2. Then re-apply `_deferred_backedge_floor` -- it is written and measured, and
   the diff is recorded in this session's history.

t/wire-c-style-for-over-a-package-scalar.t pins both, TODO'd with reason, and
keeps the LEXICAL form as a guard: `for (my $i = 0; ...)` is unaffected,
since its stamp is known during the walk.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Attempt 2 (same day): both halves built, both reverted

Both fixes work in isolation and the round trip passes. The blocker is that
DEFECT 2's fix contradicts an existing, correct behaviour.

### What was built

- `_deferred_backedge_floor` (producer): an unstamped EntryDef's floor is
  fixed by its sigil, so `join(Int, Scalar) = Scalar` is computable at walk
  time and the Phi widens honestly. Worked.
- `_loop_invariant_roots` (deparser): collect the variables every EntryWrite
  targets; treat a read of one as loop-carried. Worked -- the emitted loop
  read `$main::i` directly and terminated.

t/wire-c-style-for-over-a-package-scalar.t passed 4/4.

### Why it reverted: hoisting is REQUIRED for the other loop form

`t/deparse-loop-bound-is-evaluated-once.t` broke -- the emitted program ran 18+
iterations where perl runs 4. Measured, perl's two loop forms DISAGREE about
re-reading a mutated global:

    $n=2; foreach my $i (1..$n) { $n = 10; ... }    2 iterations  bound FIXED
    $n=2; for ($i=0; $i<$n; $i++) { $n = 4; ... }   4 iterations  RE-READ

So hoisting is correct for a foreach RANGE (perl evaluates the endpoints once
at entry) and wrong for a C-style `for` (the condition runs every pass).
Suppressing it whenever the body writes the variable is too broad: it fixes
the C-style loop by breaking the range loop.

### Three discriminators tried, none works

1. `does the subtree reach a loop Phi` -- the existing test. Blind to package
   variables, whose updates ride the memory chain.
2. `does the body write this variable` -- what was built. Too broad; breaks
   the range form, which must hoist regardless.
3. `what memory version does the condition's EntryDef read` -- measured, BOTH
   forms read an EntryWrite (the pre-loop initialisation). Identical at this
   depth.

The graphs do differ in shape -- a range condition is `NumGt(bound, Phi)` with
the bound a separate node, a C-style condition is `NumLt(EntryDef, const)`
reading the variable directly -- but that is a description of two programs,
not yet a test. Whether it generalises is unmeasured.

### What the next attempt needs

A property that says WHICH LOOP FORM this is, or equivalently whether the
condition is re-evaluated per iteration. The producer knows: it has separate
translators (`_translate_foreach_range` vs the C-style path through
`_translate_while_loop`). The deparser does not, and reconstructing it from
the graph is the open question -- possibly the Loop node should carry it.

Reverted rather than shipped: trading an honest refusal on one loop form for a
wrong answer on another is the trade the contract forbids.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
