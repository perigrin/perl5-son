---
name: tbase-coverage-is-the-producer-corpus
description: B::SoN's corpus is perl's t/ starting at t/base, not chalk's mdtest blocks; how to measure it correctly
metadata:
  type: project
---

B::SoN's corpus is perl's own test suite starting at `/home/perigrin/dev/perl5/t/base`
(9 files). Chalk's 240 mdtest blocks are the CONSUMER's corpus, not the producer's.

Correct invocation -- a bare `-MO=SoN` dumps a text render of every sub in scope,
including the B module itself:

    perl -Ilib -Iblib/lib -MO=SoN,json,package=main -- FILE

Two measurement traps, both hit this session:

- The "syntax OK" line lands on STDOUT ahead of the JSON, so a naive decode
  reports parse-fail. Strip with `sed '/^{/,$!d'`.
- `grep -c '"op"'` undercounts (it read 0 for a file emitting 680 nodes).
  Decode the JSON and sum `@{$j->{methods}{$_}{nodes}}` instead.

As of 2026-08-30 (commit 5a8fa48): 7 of 9 translate. Remaining are `lex.t`
(string eval, permanent by design) and `rs.t` (address-taken scalar demotion,
a genuinely unbuilt feature).

Related: [[graph-correctness-needs-the-optree-not-the-source]]
