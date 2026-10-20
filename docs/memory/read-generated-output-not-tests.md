---
name: read-generated-output-not-tests
description: Green tests miss whole bug classes; generating an artifact and reading it catches them
metadata:
  type: feedback
---

Generate the output and read it. Green tests are not evidence the output is
right, and adding assertions to already-green tests does not find what they
missed.

Measured across one feature (list-return, 2026-09), four bugs found this way and
zero found by the suite:

- the scalar-face `Coerce` was DANGLING — nothing consumed it. It reached the
  wire only because graph membership is BIDIRECTIONAL reachability, so an
  unconsumed node rides along if its operand points back. Visible the moment
  consumers were counted; invisible to any test asserting the node existed.
- `_graph_return_type` read `inputs->[-1]`, which silently became the scalar
  face once Return had two inputs. Suite passed, corpus unchanged. Found only by
  diffing two generated wire samples side by side.
- the `Count` counted the whole list instead of the last operand — correct only
  when leading operand count equals trailing array length, which held in the
  first three probes.
- the return branch passed no exit op, so the detector always saw undef.

**Why:** a test asserting a node EXISTS passes on the wrong node. A probe set
where two rules agree cannot distinguish them. "It is in the graph" is not
evidence anything reads it.

**How to apply:** for wire/IR work, emit a real sample and read it node by node,
counting consumers. Hand consumers a loadable artifact (see
`docs/samples/list-return.json`), not prose — they can run their loader at it.
When adding a slot to a node, grep every consumer for positional reads
(`[-1]` especially) and give the slot a NAME; chalk had three live `inputs->[-1]`
sites from this one change.

Related: [[allow-lists-fail-asymmetrically]], [[the-discriminating-property-is-arity]].
