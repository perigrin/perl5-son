---
name: a-verifier-that-reads-a-derived-flag-checks-itself
description: "Audit 2026-11-22: SoN::Verify caught 0 of 12 hand-broken wires -- it trusted mem_out, read a `record` the serializer derives, had no rule for the eval edge; mutation-test a verifier, and check a flag's content, not its presence"
metadata:
  type: feedback
---

The goal audit (docs/research/2026-11-22-memory-model-goal-audit.md, section
3) broke 12 good wires by hand. SoN::Verify passed all 12; chalk's loader
caught 2. Every wrong answer the audit found also verified clean.

- **A flag the writer derives checks the writer against itself.** `record`
  is written by the serializer for any Assign on neither chain, so a store
  that floated off both chains was a record by construction. V7 then asked
  only whether a record's targets were SSA scalars, and on v2 a `my` scalar
  kept in memory has `mem_in` and no inputs -- it looked SSA. Now a target
  with a `mem_in`, or one another read in the graph names a version for, is
  in memory, and V7 refuses the record (M1); a read of such a scalar with no
  `mem_in` is V6's (M4).
- **"Every write is a version" was asked only of nodes that already said
  mem_out.** An Assign or a sub Call that follows memory and is no version
  is now V2's (M2, M10), and `push` and its kin are versions in the
  EffectTable (M3b).
- **Effects off the chain had no rule** once v1's `effect-rides-value` and
  `fault-floating` went (stage 6): V2b `effect-floating` -- a Print, a
  builtin the table pins (or does not know), a may-fault division with no
  control_in (M3, M6, M7, M11).
- **V10 was never written:** `exc` -- every sub call or die in an eval has
  its Exc, and the way out of a thrower after a `local` puts it back as the
  eval's normal end does (M8, M9).
- **M5 (a read naming an older version) is not a broken wire:** it is
  another program, the same shape as the W2 wire that is right. It cannot
  be checked on the wire; chalk now makes every read at a version before the
  statement that kills it ([[a-read-that-names-a-version-is-half-a-rule]]).

**How to apply:** when a verifier goes to zero, break good wires by hand
and see what it misses (t/wire-verify-rejects-hand-broken-wires.t finds
each node by role, so a new producer cannot move it). A rule that reads a
flag must also check what the flag claims.

Related: [[the-wire-verifier-and-its-ratchet]], [[a-census-of-zero-wrong-is-only-its-cases]].
