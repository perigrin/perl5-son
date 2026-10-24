---
name: census-cause-entrywrite
description: 430/430 goal, cause 8 — "cannot lower op=EntryWrite" (20): a package scalar is one %Slot global (Part H5), the three typed slot families deleted; ROUNDTRIP 89 -> 94; next: $@ (2), aggregates, refs, formats
metadata:
  type: project
---

**Cause:** EntryWrite is a package scalar stored through memory, because
a sub or a later version reads it. It wasn't lowered.

**Cases held:** 20.

**Fix (chalk 82b35dd7):** chalk's own plan (Part H5 in
docs/plans/2026-08-03-effect-chain-followups.md) already said the storage
holds a VALUE and needs no per-representation kind. The i64, (ptr, len)
and double families are gone; each package scalar is now one `%Slot`
global, undef until written:
- EntryWrite and an Assign to an EntryDef box their value into the slot.
- An EntryDef read unboxes to its own reading.
- A read at a memory version is frozen there.

**Round-tripped:** 5 of the 20, ROUNDTRIP 89 -> 94. Wrong answers: 0.

**What they hit next:**
- `$@` (2) and `$` (1): punctuation names aren't legal identifiers.
- Package aggregates (`@a`, `@ISA`, `%h`).
- Ref, LocalAlias, AnonSub, a format.

**Lesson:** read docs/plans before designing (chalk's CLAUDE.md says so).
The plan had already named this fix, and the test it set ("deleting the
slot kinds is the test of whether this landed").
