---
name: a-shell-loop-can-eat-its-own-input
description: "`ls | while read f` lets an inner perl/ssh consume the file list from stdin; the sweep runs once and reports a perfect score"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-23T02:58:30.035Z
---

A `while read` loop whose body runs a program that reads stdin loses the rest
of its input to that program. The loop exits early and the sweep reports on a
fraction of the corpus.

Measured: a producer census over 986 PerlOnJava unit files reported 986/986
CLEAN. `control_flow.t` has SEVEN GAPs and was recorded clean. The corrected
run: 857 CLEAN, 129 REFUSED.

    ls *.t | while read f; do perl -MO=SoN,json "$f"; done      WRONG
    ls *.t | while read f; do perl -MO=SoN,json "$f" </dev/null; done
    for f in *.t; do ... done                                    also fine

**Why:** the inner program inherits the loop's stdin. `perl`, `ssh`, `ffmpeg`
and anything else that may read stdin will drain the pipe.

**How to apply:** redirect stdin away from the body (`</dev/null`), or use a
glob `for` loop instead of `read`. And treat a SUSPICIOUSLY GOOD sweep as a
measurement bug until proven otherwise: the check that caught this was
grepping the corpus for constructs known to be refused (9 files with
`next if`, 25 with a sort comparator) and noticing a 100% pass was not
credible against that.

[[a-sweeps-absence-is-not-evidence]] covers the silent-failure direction;
this is the same error wearing a perfect score. Both want the same reflex:
confirm the sweep MEASURED what you think before quoting it.

Related: [[clean-counts-cannot-measure-progress]],
[[truncated-output-manufactures-facts]]
