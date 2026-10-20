---
name: a-refusal-test-must-name-its-cause
description: "A test asserting a GAP passes for the wrong reason once the cause moves; assert which refusal, not that one happened"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-19T04:36:28.465Z
---

A test that asserts "this GAPs" encodes a LIMITATION, not a fact about perl.
When the limitation is lifted the test either fails (and looks like a
regression) or keeps passing against a DIFFERENT refusal one layer down.

Three of mine did this in one session:

- pinned the multi-exit merge as refusing; it became renderable and the test
  failed as if I had broken something
- pinned `next` before `last` as refusing FOR LOOP CONTROL; the loop-control
  layer was fixed and it kept passing against an unrelated statement-modifier
  gap
- pinned a bare-block continue; still refused, but the message changed

**Why:** a refusal is a statement about the current implementation. Its
message is the only thing tying the test to the cause, so matching only
`qr/GAP:/` passes for any refusal at all.

**How to apply:** match the SPECIFIC message text, and write the measured
behaviour (perl's answer vs the emitted one) in the comment so the next reader
can tell a moved cause from a real regression. When the cause does move,
update the assertion to name the new one rather than loosening the pattern --
and prefer converting the test to a round trip the moment the construct
lowers. [[removing-a-gap-can-create-a-miscompile]] is the same boundary seen
from the other side.

Related: [[clean-counts-cannot-measure-progress]],
[[a-guard-can-measure-the-wrong-quantity]]
