---
name: every-edge-found-becomes-a-corpus-case
description: "Standing rule (the user, 2026-11-25): every edge or gap found -- a wrong answer, a refusal, an audit probe's lesson -- becomes a corpus case with perl's output, alongside its probe; the 2026-11-25 inventory: 879 refusal sites, 15 with a corpus case"
metadata:
  type: feedback
---

**Rule.** Every edge or gap we find becomes a case in the corpus
(`t/corpus/mdtest/pvm/`), alongside the probe that found it: perl's output
as the expected output, B::SoN's graph filled by `tools/corpus-fill-ir.pl`.
A case B::SoN or chalk refuses still goes in: it keeps perl's output, its
refusal shows in its `ir` block (`refused:`) or as a census GAP, and it
counts as no round trip. A wrong answer goes in too and shows as DIFFERS;
it is never written down as passing.

**Why.** The audit probes compare output only. The corpus also carries the
graph, and it feeds the census, the deparser's round trip and the wire
verifier, so a case there is checked three more ways (memory-model.md: the
deparser was wrong on 13 cases the probes called SAME).

**How to apply.** With each probe, add the case. Each `GAP:` message in
either lib should have a case that triggers it. The inventory of 2026-11-25
(scratchpad `co/gaps.tsv`, script `co/inv.pl`): 879 sites (producer 286,
deparser 118, chalk 97, T2 `out()` 378). 15 have a corpus case, 648 have
none (91 of them an audit probe that triggers it), and 216 are too
interpolated to match by text. The census reports only the first refusal of
a case, so the count of covered sites is a lower bound.
