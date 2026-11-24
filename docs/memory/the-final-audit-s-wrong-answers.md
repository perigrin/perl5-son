---
name: the-final-audit-s-wrong-answers
description: "Final goal audit 2026-11-24 (read-only): gates hold, 847 fresh probes (probes/f) found 111 silent wrong answers in nine classes, all older, all with clean wires; aliases, late-made reads and dropped lvalue stores are the open design risks"
metadata:
  type: project
---

Final audit of the memory-model goal (2026-11-24;
docs/research/2026-11-24-memory-model-final-audit.md; probes
docs/research/son-ir-audit-2026-11-19/probes/f, verdicts in `_run1.log`).
Nothing was fixed: the audit changed no code.

Gates re-run and holding at a5df593 / 93c01e4c: 1451 gated probes WRONG 0,
verifier 0 on corpus and the older probes, ratchet. The 847 new probes:
SAME 557, REFUSED 173, LOUD 6, WRONG 111. All 111 were wrong at the
re-audit's heads too (`_base.log`); all 111 wires pass SoN::Verify.

**The classes** (side read off one wire each):
A copy of a shared `my` array reads the source after a call (12, producer);
B `my @c = @$l` made after a later store (17, chalk: the wire names the old
version); C a callee writes a variable then reads `$_[N]` (19); D an
assignment or ternary as an lvalue, store dropped with no GAP (14,
producer); E `for ($x,$y)` over package scalars or elements: aliases lost,
reads give 0, no vivifying (18, producer); F `chop`'s value is 1 (10,
chalk); G a foreach alias write lost when the pass dies (13, producer: the
Exc edge has no write-back); H `$_[0] = ...` on an invocant (2); I `$1` not
put back at a block's end (6, producer).

**Lessons:**

- **A probe set measures itself.** WRONG 0 on the gated set, 13% on a
  fresh one. Four audits, four fresh sets, a similar rate each time (14%, 19%, 14%, 13%). Write
  the fresh probes before believing the zero.
- **Probe a wrong answer's neighbours at once.** 14 wrong in the first 610
  became 97 more in 237 neighbours.
- **A new probe directory is read by the ratchet** (`probes/*/*.pl`). Three
  programs that print the right answer broke verifier rules (a floating
  `1/$_[0]` inside `sprintf`, a `my` aggregate, a field array); they sit in
  `probes/f/unverified/`, one level deeper, until fixed.
- **A probe named after a builtin can test another.** chalk's `chop1-3`
  all call `chomp`.
- **A saved log filter can eat the rows.** `grep -v '='` to drop the count
  line dropped every WRONG row (`got=[...]`). Count the kept rows.

Related: [[the-re-audit-s-wrong-answers-refused]],
[[a-copy-is-a-location-and-a-local-has-a-way-out]],
[[a-silent-drop-is-worse-than-a-refusal]],
[[a-census-of-zero-wrong-is-only-its-cases]].
