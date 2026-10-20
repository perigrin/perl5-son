---
name: a-shape-assertion-outlives-the-shape
description: "Tests that assert graph structure go stale when the producer gets more precise; assert the fact, not the shape that carried it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T14:23:51.097Z
---

A test that asserts GRAPH SHAPE fails when the producer gets BETTER, not only
when it gets worse. Three did in one change, and none of them had found a
defect.

Measured 2026-09-26, landing a demotion for destructive s/// on a lexical:

- `is $d->render($data), undef, 'a counted s/// ... refuses'` -- asserting a
  REFUSAL the fix removes, with a comment explaining "the graph names a
  Constant". It no longer did, so the comment was provably false.
- `is($ret->inputs->[0], $subst)` -- the return now reads a PadAccess threaded
  to the subst's memory version, which is strictly MORE precise. The assertion
  was stricter than the fact it protected: "the return must not see the
  PRE-subst value."
- an operand count that popped a trailing memory input, recognising only
  `MemStart` -- under a comment that read:

      # Checked by ROLE rather than by an allow-list of node classes: a list
      # naming only the kinds seen today passes by accident when the chain
      # grows a new memory point

  The warning and the violation were four lines apart, same hand. It went off
  by one the moment the superseded version became an `Assign`.

**Why:** a shape is how a fact is currently carried, and the producer is
entitled to carry it better. Pinning the shape freezes an implementation detail
as a requirement, so a real improvement arrives looking like a regression.

**How to apply:** write the assertion as the FACT.
- Not "the Return's input IS the subst" but "the Return does not observe the
  pre-subst value" -- walk the read back to what it observes.
- Not `isa('MemStart')` but the whole memory set, spelled as the same list the
  producer uses, so the two cannot drift.
- Where behaviour is the fact, run it: a round trip outranks any structural
  claim, and belongs in a file that can run one.

A refusal test that fails BECAUSE THE REFUSAL WAS FIXED is the mechanism
working -- [[removing-a-gap-can-create-a-miscompile]] from the safe side. The
dangerous version is when no test mentions the shape at all.

And fixing one of these by ADDING a class to an allow-list reproduces the bug
on the next kind. Replace the list with the role.

Related: [[a-refusal-test-must-name-its-cause]],
[[allow-lists-fail-asymmetrically]], [[compiling-is-not-running]]
