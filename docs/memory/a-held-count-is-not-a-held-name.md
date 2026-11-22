---
name: a-held-count-is-not-a-held-name
description: "Wire v2 stage 10: the profile is gone and every rule is hard; a count held at 1 lets another violation take its place, so what stays is held by name; a plan's table is measured on the wire before it becomes a rule"
metadata:
  type: project
---

Wire v2 stage 10 (branches `v2-s10`, 2026-11-22). Neither writer writes
`profile`; chalk's loader and `SoN::Verify` refuse a wire that has one, by
name, and hold every wire to every part (L7, L8, V11, phi-trivial, a Loop's
Phis pairing with its own inputs). New: L9 / `memory-as-value` (inputs hold
values only: no MemStart, no memory Phi as an input), and V2 / L5 for the
kinds that store whenever they run (EntryWrite, CellWrite, Delete,
ElemRestore, MakeCell) and a builtin EffectTable calls a `version`.

**Lessons:**

- **A held count is not a held name.** The producer's ratchet held probes
  `record` at 1 (pl13) and chalk's lib per graph, a graph not recorded
  printed and passed. A count of 1 lets a different violation take pl13's
  place unseen. Every rule is hard now, in both suites; what stays is listed
  by source, case, graph and rule with its reason (`%HELD` in
  t/wire-verify-ratchet.t and chalk's t/bootstrap/ir/wire-verify.t), and
  `tools/wire-verify.pl --tsv` prints each violation (`SOURCE ! CASE:GRAPH#NODE
  OP RULE DETAIL`) so the test can name it. The per-graph record
  (t/data/wire-verify-chalk-graphs.tsv, tools/lib/WireRatchet.pm) went with the
  counts. Falsify it: rename a held key and the test must fail.
- **Measure a plan's table on the wire before it is a rule.** The plan's 3.3
  says a builtin that writes (`writes` or `version`) and a LocalAlias each
  carry `mem_out`. As a hard V2 that found 66 nodes over corpus and probes:
  world writes (printf, unlink, srand, exit, select, formline, sleep, chdir,
  lock) are ordered by control and follow memory, as Print is -- the
  EffectTable's `version` column is what says a builtin is a memory version
  (stage 7 left `rand`/`srand` that way on purpose, Q13) -- and LocalAlias
  (`$_` aliased per pass) is pinned with `mem_in` and no `mem_out`: B::SoN
  forwards its binding to the body's reads of `$_`. The rule follows the
  producer's statement (`is_version`); LocalAlias is held by name in
  SoN::Verify, and making it a version is open (a placement change).
- **A refusal moves to the earliest rule that sees it.** With L8 on every
  wire, a `mem_in` naming a node listed after it is L8's (`follows N (mem_in
  or control_in), made after it`), no longer the loader's later "not an
  already-created node": a refusal test names the rule it now meets.
- **The consumer's own writers.** `Chalk::Regex::Graph` writes a graph, not a
  wire: no top level, so no `profile`; chalk's `to_json` wrote `['mem']`. A
  graph chalk wrote threads no memory (its Return names none), so the loader's
  `dowarn` guard -- the invariant only on B::SoN's wires -- stays, held by
  name.

Related: [[a-loop-is-walked-once]], [[the-loader-holds-v2-to-its-invariant]],
[[the-wire-verifier-and-its-ratchet]], [[make-the-guard-fail-on-purpose]].
