---
name: an-analysis-rewrite-is-held-to-its-old-answers
description: Before rewriting an analysis, record its answers per node as an oracle; key nodes by graph + structural id + occurrence, with the temp file's path stripped
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-18T17:00:00Z
---

Chalk's integer intervals moved from Math::BigInt bounds to native ones
that saturate at the IV range (branch no-bigint). Before touching the
analysis, t/bootstrap/ir/t1-integer-intervals-prove-nothing-new.t recorded
the old analysis's answers to the only two questions T2 asks (int_is_iv,
int_within 2**53) for every node of the census corpus and
t2-integer-intervals.t's programs. The rewrite was held to: no new proof
(sound), lost proofs listed and counted. Result: 0 new, 9 lost, all in the
synthetic edge program (values through the UV range and back).

Two traps in keying the record:
- A node's `id` is STRUCTURAL (value-numbered: `Constant|const_type=integer|value=1`),
  so two nodes share one. Key = graph name + id + its occurrence among that
  id in program_nodes order (graphs sorted by name). That is stable under
  any PERL_HASH_SEED -- check it with two seeds before trusting the record.
- Ids carry the source file's path (`site||/tmp/XXXX.pl|1|`): a tempfile
  name per run makes every key differ. Write each program to one path and
  strip the temp dir from the id.

**Why:** an optimisation analysis's answers are only ever checked by the
tests that happen to look; a per-node oracle over the corpus shows exactly
what a rewrite gains or loses, and "no new proofs" is soundness relative to
the old analysis.

**How to apply:** for any rewrite of an analysis T2 asks (intervals, types,
narrowing), record the old answers first (env-gated record mode in the
test), commit the fixture alone, then rewrite.

Related: [[a-census-of-zero-wrong-is-only-its-cases]]
