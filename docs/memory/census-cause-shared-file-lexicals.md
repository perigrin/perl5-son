---
name: census-cause-shared-file-lexicals
description: 430/430 goal, cause 3 — stores to a file lexical a named sub shares ("Assign lhs got MemStart", 60): one %Slot module global per symbol; Assign lhs 67 -> 47; ROUNDTRIP 77 -> 77; two silent wrong answers (defined over Scalar, bare return stamped List)
metadata:
  type: project
---

**Cause:** a file lexical that a named sub closes over is read and written
through memory in both the program and the sub. Chalk refused every store
to one ("Assign lhs must be ... got MemStart").

**Cases held:** 60 of the 67 Assign lhs refusals.

**Fix (chalk f65a372a, perl5-son 8b212ec):**
- Each shared symbol is one module global `@lex_<symbol>` of type %Slot. A
  store boxes the value; a read unboxes it to the reading's repr.
- Reads freeze at their memory version, including after a direct call,
  since an inlined sub may store to the global.
- perl5-son spells a second shared scalar with the same name as `c__2`.
  Two file lexicals with one name had been merged into one global.

**Round-tripped:** 0 new. ROUNDTRIP stays 77. Assign lhs goes 67 -> 47.

**Wrong answers found on the way, each red first:**
- `defined` over a Scalar was always true. An unassigned shared `my $k`
  read as defined. Defined and DefinedOr now read the Slot's defined bit.
- A scalar-context call to `sub g { return }` was stamped List, so it was
  "always defined" (backlog 7cbb3220).

**What they hit next:** builtins the backend does not lower. `push` (11)
leads, and that became cause 4.
