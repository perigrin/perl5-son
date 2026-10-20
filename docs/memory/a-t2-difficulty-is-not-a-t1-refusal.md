---
name: a-t2-difficulty-is-not-a-t1-refusal
description: "A GAP means the program does not say, not that a backend would struggle; refusing on lowering difficulty decides for every consumer"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-25T14:28:26.568Z
---

A T1 GAP means **"I cannot say what this program does."** It does NOT mean
"I cannot see how a backend would execute this."

Refusing on the second decides for every consumer, including ones that could
handle it. The IR's job is to describe the program truthfully; whether a
given target can lower it is that target's call, expressed by the consumer
declining a node kind it recognises.

Measured 2026-09-25 on `goto`. Three FACT classifications dissolved in one
sitting -- `goto LABEL`, `goto &$ref`, `goto $coderef` -- each believed on
the strength of our own refusal message rather than a measurement. Even the
hardest case is describable: a dynamic label needs a string-to-label lookup
at runtime, but the label set is enumerable from the optree
(`nextstate(A:`, `nextstate(B:`), so T1 can say what the program does.

**Why:** a refusal message is written by whoever could not build the
lowering, and it records their difficulty in the vocabulary of a fact about
Perl. Read back later it looks like evidence. "perl defers it" was our own
sentence, not a measurement -- and `goto LABEL` puts the label constant
directly on the op.

**How to apply:** when classifying a refusal FACT vs ARTIFACT, ask only
whether the answer is present in the program. If it is, the refusal is an
artifact no matter how awkward the lowering. Then make sure the wire lets the
consumer RECOGNISE and decline the shape -- removing a producer refusal
exposes consumers with no rule for it, which is
[[removing-a-gap-can-create-a-miscompile]] from the other side.

Related: [[a-silent-drop-is-worse-than-a-refusal]],
[[clean-counts-cannot-measure-progress]]
