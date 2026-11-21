---
name: a-cell-is-a-version-made-where-it-stands
description: "Wire v2 known issue 1 closed: MakeCell is _place'd; v1's writer and as_v1 hide the pin by naming what the cell follows wherever control is named, and by replaying the walk order v1 had; chalk T2 walks past a cell on the chain"
metadata:
  type: project
---

Branch `v2-s4` (2026-11-21). `_capture_cells` made a MakeCell the memory
version through `_call_memory_barrier` and never put it on the control chain:
every V2 `version-off-chain` but one, and most of V5. It is `_place`d now.
corpus2 V2 14 -> 1, V5 17 -> 7; probes2 V2 34 -> 0, V5 31 -> 4.

**Hiding a pin from v1 is more than `control_in`.** v1 must stay byte for
byte (the downgrade proof), so its writer (`_control_in`, `_on_chain` in
SoN::Serialize::JSON) names what a cell follows wherever control is named:
`control_in`, the inputs of If, Loop and Region (a Loop's entry was the
cell), Phi `predecessors`, a Region's `eval_entry` (an eval string's entry
was the cell). Then two of nine closure probes still differed, every node
the same, in another ORDER: v1's ids are a DFS over a BFS that follows
`consumers`, and the node after the cell had become the cell's consumer
instead of its predecessor's. `_v1_after_cell` puts it back where v1 met it.
**A node's position on the wire depends on consumer lists: a change to
`control_in` moves ids even where the graph is the same.**

chalk T2 refused the pinned cell ("a statement MakeCell"); it walks past it
now (chalk 1eaafd8a): a cell is made where its value is first asked, at the
version it was made at.

Related: [[the-deparser-reads-v2-through-as-v1]], [[one-constructor-places-every-node]].
