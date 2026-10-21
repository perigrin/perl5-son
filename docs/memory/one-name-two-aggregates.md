---
name: one-name-two-aggregates
description: two `my @n` in sibling blocks are two arrays; spelled by name they were one, so the second pushed onto the first's leftovers
metadata:
  type: feedback
---

`if ($a) { my @n; push @n, 1 } if ($b) { my @n; push @n, 2 }` emitted
one `my @n` in the prologue (baseline too): `1;1 2;` for `1;2;`. The
IR had two PadAccess nodes, but the wire carries no pad index, and a
pushed aggregate is spelled by its name.

**Why:** scalars are SSA values, so their names never mattered; an
aggregate mutated in place is a NAME, and two slots shared one.

**How to apply:** %SoN::FromOptree::PAD_SYMBOL renames the second and
later slots of a name (`n__2`) per CV, applied in PadAccess's ADJUST so
all 21 construction sites follow; not for slots shared by name with
another graph (closure, named sub, file lexical, `our`). Found while
lifting "a foreach over a merged binding": also a merge of two arrays
must be stamped Array (the deparser read List as a scalar), and a copy
`@l = @n` that is no `my` is pinned and marked `rebinds`.
