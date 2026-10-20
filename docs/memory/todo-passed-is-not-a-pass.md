---
name: todo-passed-is-not-a-pass
description: "prove's \"TODO passed\" on a Test2 todo-wrapped subtest is reported even when the inner assertion fails"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-09-28T17:15:51.618Z
---

A Test2 `todo '...' => sub { subtest ... }` makes prove print `TODO passed: 1`
even when the assertion INSIDE the subtest fails: the todo amnesties the inner
`not ok`, so the subtest's own summary line comes out `ok ... # TODO`, and prove
counts that as an unexpected pass.

Commit 46df9e5 claimed "this promotes the TODO in
t/from-optree-open-our-handle-round-trips.t" on exactly this evidence. Run with
`prove -lv` on 2026-09-28: the inner `is` still fails ("Failed test (with
amnesty)"), `$main::T = $eff15` and `close($eff15)` still emitted.

**Why:** the summary line is a rendering of the subtest wrapper, not of the fact.

**How to apply:** before promoting any TODO, run `prove -lv` and look for
`with amnesty` inside it. Absence of amnesty lines is the pass; the summary is
not. Related: [[make-the-guard-fail-on-purpose]], [[verify-the-harness-before-reading-its-output]].
