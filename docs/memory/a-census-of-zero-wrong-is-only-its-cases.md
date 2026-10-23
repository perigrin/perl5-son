---
name: a-census-of-zero-wrong-is-only-its-cases
description: chalk bson/llvm-corpus showed 0 DIFFERS / 0 LLI_FAIL on the corpus while class methods had 3 wrong answers and 3 chalk tests were red; letting a new class of program load needs its own probes, and the whole other suite, not a subset
metadata:
  type: feedback
---

The loader goal ended at 75 ROUNDTRIP, 0 DIFFERS and 0 LLI_FAIL, and I
called it met. A 12-agent review of the 8 commits found more:
- **Three wrong answers in class methods.** Each was confirmed through
  B::SoN, chalk and lli.
- **Three chalk tests had gone red.** I had run only the from_json-related
  tests, not the whole `t/bootstrap/ir/`.

How each wrong answer got in:
- **C1: caching any read, not just frozen ones.** The FieldAccess cache
  hit served any cached read. Only frozen reads are safe, because a read
  lowered at its first use doesn't dominate a sibling arm. Fixed by
  keeping a `_frozen_reads` set.
- **C2: a B::SoN bug.** `$n += 1` did not advance memory, so the read
  after it was the read before it. Deparse gave the same wrong answer.
  This was in perl5-son's `$field_compound` branch.
- **C3: a dropped store.** B::SoN hangs an else-less `if`'s field store
  off Start, and chalk's chain walk dropped it. Deparse already refused
  that shape ("a control node with 2 successors"). Chalk now refuses it
  as well, at lowering time. Doing it at load time refused whole files,
  because an old fixture has forks in dozens of library methods.

None of these shapes is in the pvm corpus. The census only measures its
own 430 cases.

**How to apply:**
- When a change lets a new class of program load, write probe programs
  for that class: branches, loops, calls, compound ops. Run each through
  B::SoN, chalk and lli, and compare with perl.
- Run the other repo's whole suite against its own baseline (an archive
  of the pre-change commit). Diff the lists of failing files.
- `t/roundtrip-ratchet.t` *skips* unless `SON_RATCHET=1` is set (about
  1.5 hours). "All tests successful" from `prove -lr t/` does not mean
  the ratchet ran.
