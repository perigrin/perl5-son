---
name: unknown-is-write-once-not-a-sentinel
description: "The eq 'Unknown' guards are a monotonicity/termination guard -- stamps are written ONCE from Unknown; do not unstamp a node to trigger recomputation"
metadata:
  type: project
---

`Unknown` is the TOP of the stamp lattice: a real member with defined join/meet.
The `eq 'Unknown'` guard appears **18 times** across the inference passes in
`lib/B/SoN.pm`, and it is a **TERMINATION GUARD**, not a "nobody filled this in
yet" sentinel.

The invariant, stated at `_stamp_merges`:

> The lattice has finite height and **a join only ever moves up it**, so this
> converges in a couple of passes.

The design:

1. **A stamp is written ONCE, from Unknown**, and never revised downward.
2. **Requirements are ACCUMULATED across ALL uses before anything is written**,
   so the single write is the FINAL answer, not the first-seen one.
3. **Order does not matter.** Measured 2026-09-04:
   `length($x) + $x` and `$x + length($x)` both give `meet(Str, Num) = Num`.

perigrin asked "backward inference skips any node whose stamp isn't Unknown --
that sounds like a bug" (2026-09-04). It is not: it is what keeps the fixpoint
monotone. The reasoning was undocumented at the guard sites and was written up
then.

**Why this matters for a fix:** DO NOT unstamp a node (set it back to `Unknown`)
to make a later pass recompute it. That breaks monotonicity -- the thing the
guards exist to preserve -- and it is the design perigrin has rejected. I
proposed it again on 2026-09-05 for a loop-carried Phi whose back-edge was
unstamped, and it is wrong for exactly this reason.

`_make_pad_access` leaving PadAccess Unknown is CONSISTENT with this, not an
exception: it is an un-narrowed node awaiting its single write, so backward
inference can meet the declared slot type with the use-site requirement
(`meet(Scalar, Num) = Num`). Stamping `Scalar` at construction pre-empts that
meet and comes out strictly wider -- measured, it broke
t/wire-backward-inference.t.

**Known open defect (NOT the guard's fault):** `sub p { my ($x)=@_; $x = shift;
return $x+1 }` leaves `$x` Unknown where perl observes Int -- the reassignment
binds a scalar slot to an `Array`-stamped ArgsSource. That is a defect in the
list-assign path. perigrin's call: not fixed with the guard work.

Related: [[the-discriminating-property-is-arity]]
