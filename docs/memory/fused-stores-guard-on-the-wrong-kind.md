---
name: fused-stores-guard-on-the-wrong-kind
description: perl fuses a store onto the reading op; a PadAccess-only guard drops the package form silently
metadata:
  type: project
---

perl compiles `$x = <FH>` with the sassign NULLED and the destination carried
on the reading op itself (OPf_STACKED). The destination is a SIBLING of that
op, not a kid, so it can only be recovered from the stack.

The guard that claims it required a `PadAccess`. A package scalar pushes an
`EntryDef`, so `$bar = <FH>` fell through: the target stayed on the stack, the
read's value reached nothing, and the store vanished. `my $bar = <FH>` worked
the whole time, which is what made it look like a readline bug rather than a
target-kind bug.

**Why:** the two forms are identical in the optree apart from which op pushes
the destination (`gvsv[*bar]` vs `padsv[$bar]`), so a guard keyed on the pad
class encodes a distinction perl does not make. Same shape as
[[assign-targets-are-positional]] and [[allow-lists-fail-asymmetrically]]:
the discriminating property was the FLAG (OPf_STACKED), never the node class.

**How to apply:** when a guard names one node class, ask what the package,
lexical, element and deref spellings of the same construct push. A package
target also needs `_entry_store` on top of the rebind -- a pad slot is private
to its sub, a stash entry is readable from every sub and is ordered only
through memory. And `sigil` is not universal: check the class BEFORE calling
an accessor on `peek_node`.

Found by reading emitted output, not by a failing test --
[[read-generated-output-not-tests]]. base/rs.t emitted `readline(FH);` with no
store, and 24 of its 41 tests printed `not ok`.
