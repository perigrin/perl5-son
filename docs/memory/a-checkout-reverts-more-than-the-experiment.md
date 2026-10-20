---
name: a-checkout-reverts-more-than-the-experiment
description: "git checkout on a file discards every uncommitted change in it, including verified work from earlier in the session"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T13:51:17.297Z
---

`git checkout <file>` to undo an experiment discards **everything** uncommitted
in that file, not the experiment. If verified work from earlier in the session
is in the same file, it goes too, silently.

Measured 2026-09-26. Four producer changes were working and tested (a slot
demotion, a subject read, two control pins). A later experiment in the same file
failed, I reverted it with `git checkout lib/SoN/FromOptree.pm`, and all four
went with it. The deparser half of the same fix lived in a different file and
survived, so the tree held HALF a fix and every quick check still passed:

    perl -c              syntax OK
    the corpus census    ran and produced a number
    the suite            started clean and ran for minutes

Caught only by `git diff --stat` before committing -- FromOptree.pm was absent
from a change set that had to include it. The running suite was by then
measuring a half-applied fix.

**Why:** the revert is scoped to a FILE and the intent is scoped to a CHANGE.
Those coincide only when the file holds nothing else, which is exactly the
situation that stops being true as soon as work accumulates. Nothing in the
output says what was lost.

**How to apply:** before `git checkout` on a file, ask what else is uncommitted
in it. If the answer is anything, commit the good work first -- a WIP commit is
cheap and amendable -- or undo the experiment with the inverse edit instead.

And `git diff --stat` before every commit, read against what the change was
SUPPOSED to touch. A file missing from the list is the signal; a file present
with a surprising line count is the other one.

Related: [[compiling-is-not-running]],
[[verify-the-harness-before-reading-its-output]]
