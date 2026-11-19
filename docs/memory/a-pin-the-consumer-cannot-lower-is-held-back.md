---
name: a-pin-the-consumer-cannot-lower-is-held-back
description: "Pinning the dynamic method call and a may-fault Divide/Modulo is written and tested but not on branch placement: chalk c1a48dfe refuses both as statements, costing census cases and SAME probes. It waits on branch placement-pins"
metadata:
  type: project
---

The 2026-11-19 audit's W3 (`$o->$m()` off the chain) and departure 23
(`1 / $d` floats) are producer fixes of a few lines each:

- the dynamic method call: `_pin` + `_call_memory_barrier`, with `want`, as
  a method call has;
- `_may_fault($node)`: a Divide or Modulo whose divisor is not a constant
  known non-zero (for `%`, one that truncates to non-zero) is `_pin`ned
  through `_pin_tied_read`'s hook, on control only -- it reads no memory.

Both are on branch `placement-pins` (off `placement`), with their tests
(`t/wire-dynamic-method-call-is-on-the-chain.t`,
`t/wire-a-division-that-may-fault-is-on-the-chain.t`).

**Why not on `placement`:** chalk c1a48dfe lowers every pinned node as a
statement and has no arm for these two. Measured:

- dynamic method call pinned: dyn1, dyn2 WRONG -> REFUSED ("a statement Call
  dynamic_method"), and corpus cases 012 and 055 ROUNDTRIP -> GAP: census
  426 -> 424.
- Divide/Modulo pinned: fl1, fl6 WRONG -> REFUSED, and fl3, im20 SAME ->
  REFUSED ("a statement Divide").

The goal's gate is census >= 426 and no SAME probe lost, so the two wait
for chalk to grow the arms. Then: merge `placement-pins`, rerun the census.

**Lessons:**

- **Ask the consumer before pinning.** One probe run per new pinned kind
  (two minutes) says whether it is a statement the consumer knows.
- **The floating form is "right" in the census only by shape**: 012 and 055
  call a method that returns a constant, so running it at first use is the
  same as running it in place. The count hides the class.

Related: [[the-effect-table-is-the-one-statement]],
[[the-wire-is-checked-before-it-is-loaded]].
