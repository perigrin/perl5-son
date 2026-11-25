# Audit of the SoN IR against the SSA literature (2026-11-19)

- [REPORT.md](REPORT.md): the audit. Findings, the four areas (memory chain,
  loops, calls, cross-cutting), a table of every departure from the theory
  with a verdict, 59 new silent wrong answers in 10 classes, and a
  recommended order of work marking which steps change the wire format.
- `wrong_W*.md`: script-generated listings of each wrong-answer class.
- `probes/p/`, `probes/q/`: the 418 probe programs (perl in, compared with
  chalk's output), with the run logs (`_all.log`, `_run*.log`).
  `probes/w/`: programs whose wires the report quotes.
  `probes/a/`: the 288 one-line probes of the 2026-11-22 goal audit
  (../2026-11-22-memory-model-goal-audit.md, section 2), named `au` plus the
  audit's batch letter and number (`aun1` is its batch n, probe 1);
  `_run1.log` is their sweep at producer 2d67c84, chalk 287e5da1 (55 WRONG).
  `probes/l/`: lw1-lw96, a loop body writing an aggregate after reading it.
  `probes/r/`: the 499 probes of the 2026-11-23 re-audit
  (../2026-11-23-memory-model-goal-re-audit.md, section 3), in chalk's
  `t/data/audit-probes` as `re` plus their name (`a01.pl` is `rea01`).
  `probes/f/`: the 847 probes of the 2026-11-24 final audit
  (../2026-11-24-memory-model-final-audit.md, section 3); `_run1.log` is their
  sweep (111 WRONG), `_base.log` the wrong ones at the re-audit's heads.
  The three whose wires broke a verifier rule (a55, d61, o11) sat in
  `unverified/` until branch `final-audit` fixed the producer; they are in
  `f/` now. In chalk's `t/data/audit-probes` as `fa` plus their name
  (`a01.pl` is `faa01`), gated with WRONG 0 since `final-audit`.
  `probes/cpa/`: cpa01-cpa35, the fix probes of designs A and B1
  (docs/plans/2026-11-24-copy-and-local-unwind.md), copied from chalk's
  `t/data/audit-probes` beside the audit's own.
  `probes/z/`: the 828 probes of the 2026-11-25 second final audit
  (../2026-11-25-memory-model-final-audit-2.md, section 4); `_run1.log` is their
  sweep at producer 888d71b, chalk f1d9aa74 (57 WRONG). `zlib/` holds the two
  modules the package probes load. The two whose wires broke a verifier rule
  (pa79, un75) sat in `unverified/` until branch `audit2` fixed the producer
  (pa79) and the verifier (un75); they are in `z/` now. In chalk's
  `t/data/audit-probes` as `z` plus their name (`cp01.pl` is `zcp01`), gated
  with WRONG 0 since `audit2`.
  `probes/y/`: the 1373 probes of the 2026-11-25 third final audit
  (../2026-11-25-memory-model-final-audit-3.md, section 4); `_run1.log` is their
  sweep at producer 76f33aa, chalk eca706af (146 WRONG, and `ya57`, which is
  not counted). `ylib/` holds the modules the `yd` probes load. The 39 in
  `unverified/` break a verifier rule (30) or the pre-scan agreement test (9). Not in chalk's
  `t/data/audit-probes` yet.
- `tools/`: the audit's scripts -- `ch.sh`/`runp.sh` (run a probe: B::SoN,
  then chalk T2, then lli, against perl), `d.pl`/`dump.pl` (compact wire
  dump), `census.pl` (which effects are on the memory chain),
  `memcheck.pl` (memory-version kinds, Phi arity, agreement of the two
  orderings), `stats.pl`, `ti.pl`/`ti2.pl` (TypedInvariant on a wire),
  `gen_corpus.pl`/`gen_chalklib.sh` (make the wires).

The tools were run from `/tmp/claude-0/audit/` and still name paths there;
point them at a working directory before rerunning. Generated wires (`.json`)
and LLVM output (`.ll`) are not committed: the tools regenerate them.

Theory: [docs/research/ssa/](../ssa/README.md).
