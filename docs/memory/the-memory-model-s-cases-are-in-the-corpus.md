---
name: the-memory-model-s-cases-are-in-the-corpus
description: "Branch corpus-memory: 58 memory-model cases (local vs $_[N] and refs, copies, foreach aliases, lvalue assignments and ?:, one per audit class) in t/corpus/mdtest/pvm/memory-model.md; census 41 round trip, 17 refused, 0 wrong; the deparser is wrong on 13; the corpus gate reads chalk's own corpus, not ours; a refill rewrites every file"
metadata:
  type: project
---

Branch `corpus-memory` (2026-11-25). The memory-model examples lived only in
the audit probes, which compare output. Now 58 cases in
`t/corpus/mdtest/pvm/memory-model.md` (a local addition, like
chalk-found-gaps.md), each with perl's output and B::SoN's `ir` block:
the user's `local`/alias/ordering examples, and one per class of W1-W10,
re-audit A-H, final audit A-I, audit 2 K1-K8.

- **census** (chalk eca706af): 489 cases, ROUNDTRIP 467 (+41), GAP 22 (+17,
  every one by name), DIFFERS 0, LLI_FAIL 0. Floor 426 -> 467.
- **deparser round trip**: ROUNDTRIP 463 (+33), REFUSED 13, DIFFERS 13,
  EMITS_INVALID_PERL 0. Floor 430 -> 463. **The 13 DIFFERS are the
  deparser's wrong answers, not gated**: `local` rendered as save/store/restore
  loses `$_[N]`'s alias to the saved scalar and references taken before or
  inside it; `$1` not put back at a block end; DESTROY; a loop body's read
  of the array the earlier passes stored (`0 2 3;...` for `1 2 3;...`).
- **corpus gate** (gate-green 222) is chalk's `son-corpus-wide.t` over
  CHALK's `t/corpus/mdtest/*.md`. Our pvm copy does not feed it; a case for
  it has to go into chalk's corpus.
- **K9** (a followed module's file-level code) is not taken: the corpus has
  no multi-file cases.
- `tools/corpus-fill-ir.pl` rewrites every file it is given: the other files
  had drifted (Subscript's pinned flag, tmp paths). Fill a new file in a
  scratch directory named `pvm`, or revert the rest; a refill of all of
  them is its own commit.
- The wire verifier: 489 corpus wires, 1155 graphs, 0 violations; baseline
  rows raised.
