---
name: a-sweeps-absence-is-not-evidence
description: A file missing from an oracle sweep listing may have timed out, crashed, or passed — they look identical
metadata:
  type: feedback
---

**A file's ABSENCE from an oracle sweep listing is never evidence of a
pass.** A per-file timeout, a crash, and a genuine ROUND-TRIPS all produce
the same thing: no line.

I made this mistake three times in one session:

- `base/lex.t` reported as ROUND-TRIPS twice. The sweep's `timeout 110`
  killed it mid-file both times.
- `comp/filter_exception.t` and `comp/require.t` written into commit
  `e1d9963` as "DIFFERS -> ROUND-TRIPS". Checked out at that commit in a
  worktree afterwards: one DIFFERs, the other GAPs. Neither moved.

**Why:** the sweep was started BEFORE the last edit and finished after, so
its output described a tree that no longer existed. Reading it as the
committed state is the error, not the sweep itself.

**How to apply:** before quoting a sweep in a commit message, either start
it after the final edit and let it run to completion, or re-measure the
specific files being claimed. Prefer an explicit grep that prints a line
for EVERY file (including a marker for timeout), so absence cannot be
silent.

Related: [[clean-counts-cannot-measure-progress]] — same family: a count
or a listing is a report about one moment, not a property of the code.
