# Census cause: a short-circuit nothing typed (360 -> 361, pin c583f12b)

**Causes:** "And.LHS[Boolean->Unknown]" (143) and
"grep test[Unknown->Boolean]" (180).

## What changed (chalk 5222aa98, c583f12b)

- **A reference arm** (`$e == $p && $ag`, an ArrayRef) is boxed to the
  Scalar as a scalar arm is.
- **A method call nothing typed** (`blessed($_) && $_->ok`) is held as a
  Scalar, which is what a run-time dispatch gives. An arm lowered as
  something else is boxed to what the merge decided (`_held_as`).
- **A grep test nothing typed** is read as it was lowered.
- **Found by a probe, not a census case.** `($c && $k->n) ? ..` runs the
  call in an If's arm, and the && is read after the merge. Lowered as a
  second short-circuit there, it took a value its block was not dominated
  by (LLI_FAIL). It is now a phi at the If's merge block, recorded per
  Region by `_process_if_node`. Sides of two reprs are refused by name.
  - A gotcha on the way: the If's test and the &&'s left side are one node
    by id but two Perl objects (the loader copies), so compare ids, not
    refaddrs.

**Round-tripped:** 180. 143 now stops at a value nothing typed elsewhere
in its sub (lattice TOP).
