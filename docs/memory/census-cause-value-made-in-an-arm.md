---
name: census-cause-value-made-in-an-arm
description: 430/430 goal, cause "an inlined sub's value is made inside one of its arms" (6) — a loop's exit Phi in an arm is lowered there; push by tag; a loop body's cached values dropped after it; calls in eval bodies carry eval_id; installed SoN::Deparse goes stale under plain prove; ROUNDTRIP 184 -> 186 of 431
metadata:
  type: project
---

**Cause:** "an inlined sub's value is made inside one of its arms (an if
as its last statement)" held 6 cases at dac75cce (069, 097, 155, 156,
173, 205).

**What 069 was:** `if ($op) { return "early" } for (...) { push ... }
return "@chain"` -- B::SoN makes the rest of the sub the else arm, so the
join reads the exit memory Phi of a loop inside that arm. The pre-check
in _lower_inlined_structure allowed an if's merge in an arm, not a
loop's exit; a loop in an arm is lowered there, with its exit.

**Built (chalk 42afb52a, perl5-son 9bf4ba1):**
- a Phi of a Region a Loop heads is allowed in an arm (069);
- push of a Scalar or undef value appends its Slot (069's next stop);
- A LOOP BODY'S CACHED VALUES ARE DROPPED after the back-edge: they were
  served after the loop, which the body does not dominate. Pre-existing on
  base (4-line repro), reached by pvm 130 once push lowered it -- it went
  to LLI_FAIL before the fix. Frozen reads are kept.
- a Call in an eval's body carries that eval's eval_id (B::SoN, via the
  factory while $EVAL_ID is set); chalk refuses one whose eval is not
  open as a branch. Before it, a try in a loop calling a dying sub exited
  255 (173), and an eval in a loop calling one said "ran" -- a probe-only
  wrong answer since the block-eval pin.

**Result:** 069 and 130 round-trip (184 -> 186, three runs agree). 173
is refused by name. Still on the cause: 097, 156, 205; 155 on "Phi before
structure".

**Lessons:**
- a fix that lowers a case further can turn a GAP into an LLI_FAIL --
  watch the bucket, not just ROUNDTRIP;
- `prove t/...` without -l loads the INSTALLED SoN modules for in-process
  code; after changing Deparse, `make install` (the bson session's
  workflow) or a suite run tests the stale copy.
