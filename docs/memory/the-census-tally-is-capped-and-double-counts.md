---
name: the-census-tally-is-capped-and-double-counts
description: "chalk-lib-roundtrip's cause tally shows only the top 12 and counts a package's graph once per module that loads it"
metadata:
  node_type: memory
  type: reference
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-14T21:29:59.936Z
---

tools/chalk-lib-roundtrip.pl `-v` prints only the 12 most frequent causes per bucket (`[0 .. 11]`), with no line saying the rest were dropped. At 9741006 the top 12 covered 76 of 94 skipped graphs.

SKIPPED_GRAPHS also counts each `B::SoN: skipped` line per translated module, and translating a module translates every package it loads. So a graph in a widely used package is counted once per loader: 94 lines were 70 distinct graphs (`sort -u`). Rank work by distinct graphs.

To get the full list: run the producer per module (the census's own command line, `-MO=-q,SoN,json,not_package=SoN` from the chalk snapshot dir) and keep every skipped line. Render each REFUSED module's JSON to get its render cause, which the census prints only as a capped tally too.

Related: [[verify-the-harness-before-reading-its-output]], [[clean-counts-cannot-measure-progress]].
