---
name: crashes-mask-gaps
description: An internal crash that fires before a GAP hides the real diagnosis; two instances found 2026-08-30
metadata:
  type: project
---

The producer's most damaging failure mode is not a wrong answer or a refusal --
it is an INTERNAL CRASH that fires BEFORE the honest GAP would have. The
refusal never runs, the real diagnosis is lost, and the error names internals
(`Stack underflow at StackSim.pm line 25`) so a reader hunts a simulator bug
instead of an unhandled construct.

Two instances found 2026-08-30, with DIFFERENT root causes despite identical
symptoms -- do not assume one cause from one symptom:

- **6abca2c, structural.** The generic op handler popped `pop_count` operands
  BEFORE checking `%UNBUILT_OP_GAP`. `goto` is `pop_count=1, node_type=undef`,
  so it popped an operand it lacked and underflowed above its own (correct,
  long-present) GAP entry. ANY refused op carrying a pop_count masks its own
  refusal this way. Fixed by checking the GAP first.
- **b8552e6, a missing handler.** `eval BLOCK` compiles to `entertry`/
  `leavetry`, NOT `entertrycatch` (which is perl's `try/catch` feature).
  `entertry` was registered BRANCH with no handler, so the branch-skip stepped
  over the body and `leavetry` popped nothing. Every form of block eval had
  been crashing.

Both were found while chasing what looked like a `$@` bug. `$@` alone
translates fine; it was a red herring twice.

**When a test asserts `dies`, assert WHAT it dies with.** A `qr/GAP/` check
would have caught both years earlier; a bare `dies {}` passes on a crash.

Related: [[graph-correctness-needs-the-optree-not-the-source]]
