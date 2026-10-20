---
name: batch4-paused-2026-10-17
description: State of the chalk-lib round-trip batch-4 merges when perigrin paused work on 2026-10-17 until Monday 2026-10-19
metadata:
  node_type: memory
  type: project
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-17T04:47:57.281Z
---

Paused by perigrin on 2026-10-17 ("pause till Monday"). Agents had stopped on the monthly spend limit, which resets 2026-10-19 15:00 UTC.

- **rt2** (~/dev/perl5-son-rt2) is at fb77fbb: renderctl merged. COMPILES 150, SKIPPED_GRAPHS 76, gate 3 SAME 488, corpus 310. Floors raised (corpus 310, COMPILES 150).
- **integ9/substcap** (scratchpad/integ9, ce608be): substcap merged onto fb77fbb, plus 29 corpus cases covering the renderctl and substcap gaps. My verification run (scratchpad/integ9-verify.txt) has finished. The ratchet PASSES: corpus 339, COMPILES 151, SKIPPED_GRAPHS 70, gate 3 SAME 488, 0 corpus drift. The suite FAILS on one test, t/deparse-while-readline.t test 1, and the cause has not been looked at. Fix that first. Once the suite passes: fast-forward rt2, then cherry-pick iteralias 02d7c8c (the bare-loop truthiness fix) and re-verify.
- **gap6/rendermisc** (62325ef): slice-read pinning fix and corpus cases are committed. Still needs its ratchet run and a second adversarial verify; the first verify found the slice-ordering miscompile, which this commit claims to fix.
- **gap6/unproven** (8bbacb2, with an uncommitted chalk-found-gaps.md): round-2 coarse seal fix, never measured. Verifier holes A–F are in scratchpad/adv7/. Drop the branch if 0 of its 7 graphs survive.
- **gap6/iteralias**: drop the alias rule (0 of 5 graphs, SKIPPED 115); keep only 02d7c8c.
- **ternalias**: dropped.
- Not yet done: record batch 4 in docs/plans/2026-09-30-chalk-lib-round-trip.md. It covers the drops and the base-wrong open items from the verifiers: slice re-read after a store, void call bound as a scalar, whole-hash read after a store, a `$_[0]` ref-keep losing a write, `ne` write-back on overloads, `my ($v) = %h`, and the shift leaking into a returned list.

Related: [[env-on-path-is-a-stub]], [[the-census-tally-is-capped-and-double-counts]].
