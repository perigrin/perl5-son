---
name: landing-work-in-a-peers-repo-needs-a-commit
description: "Permission to contribute is not permission to leave an uncommitted file in someone else's working tree"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T10:27:53.152Z
---

Permission to land work in another project's repository is NOT permission to
edit in place and leave it uncommitted. An uncommitted file sits in their
`git status` where their next `git add` can sweep it into an unrelated commit.

Measured 2026-09-26: contributed a conformance case to pvm's corpus by writing
the file directly. They found it in `git status` and said so -- "I could as
easily have swept it into an unrelated commit with a `git add`. It worked out
because I read the diff before staging."

**How to apply:** commit on a branch in their repo and tell them the branch
name, or at minimum name the path in the same message that announces the work.
Never leave the delivery implicit.

AND RUN THEIR WHOLE SUITE, not a `-run` subset built from your own reading of
their docs. I filtered on the two tests I could name from their FORMAT.md and
missed `TestCorpusRatchet` -- which is the test that notices a case ARRIVING,
so it is exactly the one such a filter selects against. The gap in what I knew
chose the filter.

That is [[verify-the-harness-before-reading-its-output]] applied to a test
filter: a `-run` pattern is a harness, and a subset chosen from partial
knowledge measures the part you already understood.

Related: [[a-sweeps-absence-is-not-evidence]]
