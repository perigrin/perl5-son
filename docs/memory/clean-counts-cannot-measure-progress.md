---
name: clean-counts-cannot-measure-progress
description: "A file's GAP count is a first-failure report, not a blocker count -- rank by defects fixed instead"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-04T01:31:22.713Z
---

Do not rank corpus files by "how many GAPs they have", and do not report
CLEAN/PARTIAL/NONE counts as a progress metric.

The translator ABORTS A CV AT ITS FIRST GAP. For perl's `t/comp/*.t` the failing
CV is almost always `main::__PROGRAM__` -- the entire file body -- so one visible
GAP means "the whole program stopped somewhere", with everything after it
unexamined. Measured 2026-09-04: nine of ten PARTIAL files in t/comp report
exactly one visible GAP and one failing CV.

`comp/parser.t` reported "1 GAP" FOUR TIMES in one session while four different
blockers were cleared from it (`exists &sub` -> `foreach over an empty list` ->
`write`/format -> `s///e` in a loop body). It is still PARTIAL.

The only place a count is real is SUB BOUNDARIES: separate subs translate
independently, so a blocker in one cannot mask a blocker in another.
`comp/proto.t` genuinely has >=3, because they are in different subs.

**Why:** a blocker count derived from GAP messages measures CV GRANULARITY, not
problem count. A file of small subs reports honestly; a file that is one big
program body reports 1 no matter how much is wrong. Two rankings built on it this
session were structurally unknowable, not merely optimistic.

**How to apply:** report defects fixed and constructs lowered, with the measured
before/after behaviour for each. Mention corpus status only to show no
REGRESSION, never as the headline. perigrin chose this over building a
per-statement census (2026-09-04) -- the census would give a true blocker count
but costs hours; fixing root causes directly has been finding real silent
miscompiles.

Truncation bisection does NOT substitute: deleting 10% of a file until it goes
CLEAN cannot distinguish "removed the blocker" from "removed the code".

Related: [[tbase-coverage-is-the-producer-corpus]], [[crashes-mask-gaps]]
