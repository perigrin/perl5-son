---
name: a-foreach-alias-write-is-a-store-where-it-stands
description: "Branch loop-writeback: a loop learns at sealing an aggregate its body wrote after a read (the walk's own mark, not an op scan); a foreach alias write is a store to the element where it is made, not a pass-end write-back that `last`/return/a label skipped; the alias read after another kind of store is refused by name"
metadata:
  type: project
---

Branch `loop-writeback` (2026-11-23; producer cc4e0db, 2430ead; chalk
fff90e52; baseline section 20). Two silent wrong answers, both at d142906.

1. **A read early in a loop body flattened a literal the body wrote later.**
   Closed by learning: see [[pending-bug-foreach-write-back-later-in-a-loop-body]].
2. **A foreach's write-back was lost on a pass left early.** The alias write
   was stored at the end of the pass: `for my $e (@a) { $e .= "x"; last if
   ... }` printed `1 2` for perl's `1x 2`, and so did a return, `next`/`last
   OUTER`, a callee's `$_[0]` before a `last`; and a callee reading `@a`
   mid-pass saw the element before the write. The user chose: store at the
   write. `StackSim::define` runs a key's `%ON_DEFINE` hook, which the
   foreach walker sets, local to the body walk; a demoted iterator (a call
   argument) stores its slot after each call passed it (`%AFTER_CALL_PASSING`).

**Lessons:**

- **The walk's own mark is the class.** Listing the op shapes that write an
  aggregate misses some (TARGMY, a gvsv `$_` with no MOD flag); checking at
  sealing whether the walk marked a literal it had flattened catches every
  kind, the ones not listed included (slices, map/grep `$_`, a `$_` callee).
  The probes are a list; the check is not.
- **A write-back at the pass end is skipped by every early exit.** An effect
  that belongs at the write must be made at the write; `next` was right only
  because it goes to the latch.
- **A store mid-pass needs its operand read pinned before it.** The pass's
  element read floated, and the deparser spelled a value made from it after
  the store ("an element read in a loop is spelled after a store"). Pinned at
  the pass top, three refusals in the deparse tests became round trips.
- **A hook on a binding fires on binding the walk makes for itself.** A
  loop's Phi bound at its exit was stored inside the body (`$x = $x->p` in
  an inner `while`: `N=HASH` for `u`); a loop's Phi is never stored -- its
  inputs were stored where they were made. snapshot copies bindings, it does
  not make them (`bind`).
- **A new store must be known to the arm scan.** An if/else writing the
  alias was lowered as a select, its stores hung off the control before it
  (wire invariant L4). `_arm_advances_control` asks `_op_writes_key` for a
  hooked key. A per-op gate on `$ARM_PINS` was tried and dropped: a `next
  if` tail is walked as an arm with `$ARM_PINS` 0, and its store was lost.
- **Store at the write is half of "the alias is the element".** A read of
  the alias after the element is changed another way (an element store, a
  store through a reference, a callee closing over the array) reads the
  walk's binding, not the element: `1y2y` for perl's `q2y`, WRONG at the
  base. Refused by name ("... may store into the array another way"); a call
  is refused only when its MOD set may reach the array
  (`ModSets::array_place`), so a callee that only reads stays lowered.
  `_list_is_private` does not see a named sub closing over a file lexical;
  widening it refused those reading callees, so it was left alone. The other
  half -- reads of a written alias load the element -- is the way to lower
  them.
- **Run every new probe at the base too.** The scratch probes next to the
  fix were WRONG at the base (41 of 96 lw probes); without the base run they
  would have read as regressions or gone unnoticed.

Related: [[a-loop-is-walked-once]], [[the-foreach-alias-is-a-reference]],
[[a-local-in-a-loop-is-restored-on-every-edge]].
