---
name: a-read-after-a-loop-needs-the-exits-memory
description: A loop must carry memory through its header AND its exit, or the read after it is the body's read from the top of the last pass
metadata:
  type: feedback
---

`for (@a) { $h{a}++ } print $h{a}` printed 2 for perl's 3. Two defects, one
symptom. The header memory Phi was made only when `_body_stores_memory`
recognised a store by op name, following `->next` from the body's start --
a `multideref` increment, a field store and a store behind an `and` were all
missed. And with the Phi, the read after the loop at the header's version
hash-consed with the read at the top of the body: one node, a pass behind.

**Why:** in SoN a node reading the header Phi is the value at the header, and
a read "after the loop" at the same version IS that node. The exit needs its
own version -- a memory Phi on the exit Region -- so the read after the loop
is a different node, placed after it.

**How to apply:** decide the header Phi from the scout's own walk (did its
sim's memory move?), not from an op-name scan; always merge memory at the
exit when the loop carries it. Several refusals existed only to avoid this
("a hash element read and store" over an unproven list); re-test refusals
whose comments describe it. Related: [[a-memory-phi-must-be-marked]].
