---
name: census-cause-closures
description: 430/430 goal, "cannot lower op=AnonSub" (5) -- a closure called while the sub that made it runs; CellWrite was silently dropped; ternary of a number and undef boxes to Scalar
metadata:
  type: project
---

**Cause:** "cannot lower op=AnonSub" (5: 011 027 128 399 407), plus
"Call indirect" (4). Five shapes again; 128, a callback closure over a
signature parameter passed down to walk(), was the one in reach.

**Built (chalk):**
- An AnonSub ARGUMENT is not lowered as a value. It is bound to its node;
  `$cb->(...)` (dispatch_kind indirect) resolves through the bindings to
  that AnonSub and is lowered as a direct call of its sub. Analysis
  attaches the anon sub's metaobject to the AnonSub node (set_sub), the
  same one a direct Call naming it gets.
- CAPTURES: a MakeCell's variable is a location, found through the cell's
  memory version (Assign to a PadAccess of the cell's name). Outer
  CellWrite stores there and outer CellRead loads there. The closure's
  CellReads are bound to loads at call entry.
- Where the cell is: `_local_slots` is scoped per inlined frame, so a
  capture read inside the callee's frame found a FRESH, EMPTY `my $k`.
  The creator's location pointer is stashed when the AnonSub is bound as
  an argument (in the creator's frame), and used for a closure reached
  that way. A directly-called closure uses the current frame. A stale
  map entry gave 128 "22" for "23" (a second only() read the first's
  $want); _cell_storage always resolves in the current frame.
- CellRead stamped by its use (loader): Num under numeric ops, Str under
  string ops, else Scalar, as B::SoN types an address-taken read.
- Analysis: a TernaryExpr whose arms are all plain scalars with no join
  (Num and Undef) boxes to Scalar. ListAppend stores a Scalar element as
  its Slot.

**Found on the way:** CellWrite on the control chain was SILENTLY DROPPED.
process_control_node only dies on is_fixed nodes, and CellWrite is
neither a statement node nor fixed. `$k = 4` after a closure over $k was
lost. It's now an explicit store.

**Perl precedence bite:** `!grep {...} @a && !grep {...} @b` -- grep's LIST
swallows the rest. Parenthesize.

**Refused by name:** a code ref used as a value (returned, stored, in a
list), a closure that writes its capture, @_ read as a list holding one.
Forwarding a code ref through a second sub was tried and dropped
(untested shape: an untyped call result).

**Swept for others:** every corpus case was run with the ops that fall
through process_control_node silently logged. Only value nodes appeared
(ArrayLiteral/HashLiteral pinned as allocations, Subscript, TernaryExpr,
Coerce, FieldAccess), which are lowered at their use. CellWrite was the
only dropped effect.
