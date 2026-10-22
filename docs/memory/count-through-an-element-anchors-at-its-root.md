---
name: count-through-an-element-anchors-at-its-root
description: `scalar @{ $self->{s} }` before a push was spelled after it; the list-deref stale pass gave up on a Subscript reference instead of walking to the variable it came from
metadata:
  type: feedback
---

The list-deref stale pass anchors a read at the version for a
Parameter, a PadAccess with one Assign def, a Phi or a node made on the
chain. A reference that is itself an element read (`$self->{s}`) hit
`next`. The count was left live and spelled after the push, so
LLVM::Context named every global one index too high.

Fix: walk floating entry-version Subscripts down to their container
before choosing the anchor.

Separately, `do { use bytes; length $x }` lost its pragma. Length now
carries `bytes` (from the nextstate hints, 0x8), and the deparser
spells it back inside a `do` block.

**How to apply:** a reference can be any pure expression rooted at a
variable. Resolve to the root before classifying it.
