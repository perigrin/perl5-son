---
name: a-cell-is-a-version-made-where-it-stands
description: "Wire v2 known issue 1 closed: MakeCell is _place'd; v1's writer and as_v1 hide the pin by naming what the cell follows wherever control is named, and keep v1's node order by when each consumer edge was made; chalk T2 walks past a cell on the chain"
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
was the cell). Then graphs still differed, every node the same, in another
ORDER: v1's ids are a DFS over a BFS that follows `consumers`. Pinning moved
edges: what follows a cell became the cell's consumer instead of its
predecessor's, and the cell became a consumer of its predecessor by its pin
(at Start it had been none). Putting the successor "right after the cell"
fixed the probes and failed 11 chalk graphs (three cells in a row; a value
consumer registered between). Exact: each consumer edge carries when it was
made (`Node::consumer_seq`, one count over all nodes), and v1's writer
(`_v1_consumers`) puts the moved edges back on what the cell follows, sorted
by that count. t/wire-v1-hides-a-cell-pin.t is the fast check; the full one
is the downgrade proof over chalk's lib.
**A node's position on the wire depends on when its consumer edges were
made: a change to `control_in` moves ids where the graph is the same. Run
the downgrade proof over chalk's lib, not the probes alone.**

chalk T2 refused the pinned cell ("a statement MakeCell"); it walks past it
now (chalk 1eaafd8a): a cell is made where its value is first asked, at the
version it was made at.

Related: [[the-deparser-reads-v2-through-as-v1]], [[one-constructor-places-every-node]].
