---
name: a-list-assign-is-placed-by-where-its-targets-live
description: "The aassign fallback places its Assign by each target's storage class (node kind and sigil), never by a stamp; a parameter bind and an SSA rebind stay records; copies are element reads; the declared type of a pad slot is its sigil's"
metadata:
  type: project
---

W2 of the 2026-11-19 audit (branch `placement`, f4ed8f1). The fallback pinned
by a list of node kinds and asked "aggregate?" of the STAMP. Now
`_target_storage($node, $ctx)` answers `ssa`, `memory`, `aggregate`,
`element`, `package` or `skip` from the node that names the place, and the
Assign is `_place`d when any target is not `ssa`/`skip`.

**Still a floating record, on purpose:**
- every target an SSA `my` scalar bound by position (`my ($a, $b) = (1, 2)`);
- a parameter bind, `my ($self, %opts) = @_`: both consumers bind it at sub
  entry and the wire has no flag to say so. Placing it made the deparser emit
  `my @stack = ($root)` above `($root, %opts) = @_`.
- package scalars bound by position: `_entry_store` stores each; the Assign
  beside them is a record (SoN::Verify still counts it floating: 4 probes).

**With it:**
- `_note_literal_mutation` takes slices and whole named literals; without it
  a placed `($a[0], $a[1]) = ...` was followed by a `join` of the literal's
  first inputs.
- An aggregate has no position by its SIGIL (`_flattens`): `my (@rest, $f) =
  (1,2,3)` bound `$f` to the constant 2.
- A copy is an element read at a version. `my ($f) = @r` bound `$f` to the
  array node; it is `Subscript[@r, 0, memory]` now, as `($x, $y) = @_`
  already was, and the record names those reads, not the bare array.
- `_declared_slot_type` reads the sigil: `@` is Array, `%` Hash, written
  whatever the uses require. MakeCell's operand row is `List`, or an honestly
  typed `my @a` was coerced to Scalar on its way into its cell (chalk then
  refused "a captured variable that is not one kept in memory").

**Lessons:**

- **A probe can match perl because the dropped store was in the arm not
  taken.** wa21 (`($a[0], $a[1]) = (10, 20) if @ARGV`) went SAME -> REFUSED.
  It was never right; run with an argument it printed the wrong array.
- **Typing a container honestly moves every table row that took it for a
  value.** One row (MakeCell) here; find them by diffing wires for new
  `Coerce` nodes whose operand is a `@`/`%` PadAccess, before trusting a
  green suite.
- **chalk c1a48dfe refuses a placed element, slice or cell list assign** ("a
  list assignment to an array or hash"). The 15 W2 probes are REFUSED, not
  SAME, until it has that lowering.
- **`is` on two array refs in Test::More compares addresses.** Use
  `is_deeply`, or Test2::V0's `is`.

Related: [[a-list-assign-into-an-aggregate-is-placed-or-refused]],
[[one-constructor-places-every-node]], [[assign-targets-are-positional]].
