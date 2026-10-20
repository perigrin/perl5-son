---
name: the-triage-has-two-questions
description: FACT vs ARTIFACT needs "who needs to know?" after "does the program say?"; a lattice position is not a missing answer
metadata:
  node_type: memory
  type: feedback
---

Classifying a refusal FACT vs ARTIFACT takes TWO questions, and the first one
alone gives the wrong answer:

1. Does the program say? (the one [[a-t2-difficulty-is-not-a-t1-refusal]] asks)
2. **Who needs to know?**

Measured 2026-09-26, wrong twice in one session by stopping at (1):

- **map body arity.** Nothing in `map { two($_) }` says how many values `two`
  returns -- a runtime property of the callee. Looked like a FACT. But NOBODY
  COUNTS: the emission renders `(@acc, contribution)` and perl flattens, exactly
  as the source does. The refusal's own rationale named "a consumer counting
  inputs", and ours counts `scalar(@acc)` at runtime. ARTIFACT.
- **glob assignment.** `*X = shift` binds a slot chosen by the operand's runtime
  type; one callsite binds `@` on one call and `$` on the next. Looked like a
  FACT, and I wrote it down as one. But THE STAMP NAMES THE SLOT -- the lattice
  already relates `ArrayRef/HashRef/CodeRef/ScalarRef/GlobRef -> Ref ->
  Scalar`, so a `Scalar` stamp says "one slot, kind determined at runtime",
  which is a statement. ARTIFACT.

**A LATTICE POSITION IS NOT A MISSING ANSWER.** Both cases had a mechanism that
read the right field and then treated an imprecise-but-honest value as absent.
The glob pass does `$SLOT{$type}` -- an exact-match hash of four keys -- against
a lattice whose whole purpose is relating those keys to their parents.

**Why:** question (1) is about the PROGRAM, and it is the one a refusal message
is phrased in ("not known until runtime", "perl itself defers the choice").
Question (2) is about OUR PIPELINE, and it is the one the refusal was actually
written from. Only (2) distinguishes "the IR cannot say this" from "I could not
see how to lower it".

**How to apply:** after establishing the program does not say something, find
the consumer that needs it and check whether it exists. If the answer is "the
emission", try emitting the source spelling -- perl's own deparse is the oracle
for whether that round-trips. If the answer is "a backend", that is T2's
declining, not T1's refusing.

Related: [[a-refusal-test-that-only-translates]],
[[a-t2-difficulty-is-not-a-t1-refusal]],
[[unknown-is-write-once-not-a-sentinel]]
