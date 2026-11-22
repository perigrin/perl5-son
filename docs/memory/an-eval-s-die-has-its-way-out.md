---
name: an-eval-s-die-has-its-way-out
description: "Wire v2 stage 8: each node that may die in an eval has an Exc carrying the restores of the locals live there to a catch Region where $@ is stored; what the lowering, the deparser's adapter and the old refusals taught"
metadata:
  type: project
---

Wire v2 stage 8 (branches `v2-s8`, 2026-11-22). Profile `["mem","eval"]`.
In an eval's body (block eval, try, known string eval, run-time string
eval) each node that may die -- an Unwind, a sub call (through
`_call_memory_barrier`), a may-fault Divide/Modulo, a read pinned because
it may die -- gets `_exc_edge`: an `Exc [T]`, and on it the restores of
the eval's own `local`s live at T, from the memory after T. `_catch_way`
merges the edges at a catch Region (`fields.catch`), stores `$@` from the
Exc (a Phi of them where several); the join takes the body's end (where
`$@ = ""` is stored now), each return, and the catch. A die where no eval
of its graph is open restores the live locals first (`_pin_die`). chalk
lowers each Exc as the block its statement's dying branch goes to
(`exc_block`), walks the restores there, merges at the catch, then the
join; a die of one value that may be a reference stores the value itself
(`t2_die_value`): ex1-ex4, ev6, lo2, lo16 went SAME.

**Lessons:**

- **The statement a die belongs to is the one being lowered -- in that
  function.** T2 lowers a callee while lowering its call; the callee's walk
  left `$b->{stmt}` at its own Return, and the caller's dying branch looked
  for that Return's Exc. `local $b->{stmt}` where a function is lowered.
- **A list slice of nothing is nothing.** `map { ( grep {...} 0..$#p )[0] }
  @ways` drops a way no pred matches instead of giving undef: every later
  way shifted, and the catch's way in was taken for a return. Use `my ($i)
  = grep ...; $i`. (merge_at and join_jumps have the same idiom.)
- **What died is made before its dying branch.** The way out's memo is
  taken in after_call, before the call's value is memoised; the join's
  common memo then lacked the call, and a try whose value was read on the
  body's way refused (corpus 137). The thrower's own value is added at the
  close.
- **Two ways out at one memory version hash-cons their restores** into one
  node, pinned twice (`_pin`'s GAP). Edge restores are `make_unique`
  (`$EXC_EDGE`), and so are the restores before a die in two arms.
- **A refusal can be narrower than the hazard it names.** W6 refused a
  sub's own die under a local and said so; a die in a sub it CALLS there
  (`sub t { local $g = 2; u() } eval { t() }`) was a silent wrong at base
  (`2` for `1`) that no probe had. The die-of-its-own case is fixed by the
  restore before the Unwind; the call case (the plan's Q9: a rethrow pad)
  is refused by name now, only where the callee may die (a direct call of a
  wire sub with no die, faulting division or dying deref in its closure is
  let through: lo16).
- **A body that died at its end has no way into the join**, but dead code
  after a die (ev12's `$g = 3`) is still pinned after the Unwind: that end
  stays a way in (dead), or its store is a version nothing reaches (V3/L4).
- **The deparser reads v1 through `as_v1`**, which drops each Exc, what
  stands on it, the catch, the `$@` store and the clearing at the body's end
  (the clearing became the body's last effect: `eval { push @a, 1 }` would
  have pushed twice); the deparser round trip stayed 430. Its rendering of a
  `local` under a die is still wrong (it spells save/store/restore, and the
  die skips the restore) -- as before.

Related: [[the-loader-holds-v2-to-its-invariant]], [[wire-v1-is-gone]],
[[a-refusal-test-must-name-its-cause]].
