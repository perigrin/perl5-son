# Census cause: element read across a branch-guarded store

**Cause:** "element read across a branch-guarded store needs a memory-Phi"
(`_scan_memory_shape` sets one graph-wide unsafe flag, and then every element
read whose memory is not a Phi is refused). It held 125, 177, 191 and 224.

**Round-tripped:** 125, 177, 191 (266 -> 269). 224 now hits "an inlined
argument is a HashRef where the callee reads a Object".

## What was wrong

The flag is meant for a store the producer left out of both the effect chain
and every memory-Phi. Two walks in the scan missed stores that *were* ordered:

- **Region inputs:** the walk back from the Return followed a Region's inputs
  only when they were control-flow nodes or Assigns. An arm that ends in
  another effect (a `local`'s ElemRestore, a print) hid the arm's stores. A
  Region's inputs are all control predecessors, so now all are followed (177).
- **Stores before the merged one:** only the last store of an arm or a loop body
  is an input of the memory-Phi. The stores before it reach that store by
  control. Each memory-Phi input is now walked back along `control_in` to the
  arm's start, and every Assign on the way counts as merged (125 `//=` under an
  `if`; 191, two stores in a loop body).

## Lessons

- A graph-wide refusal flag is only as precise as its walk. When one shape
  trips it, every read in the graph refuses, so one fix can free several cases.
- A Loop's back edge is not among its inputs (the loader does not rebuild it), so
  "data-reachable from the Return" excludes every loop body. Any rule keyed on it
  misfires in loops: the read-modify-write rule (`$h{a} = $h{a} + $i` in a loop)
  is the next one to fix, flagging only a store-back that is neither on the
  chain nor merged.
- `_is_memory_phi` does not know ElemRestore, so a loop that restores a `local`
  has a "value" phi for its memory (lo8): open.

Tests: chalk `t/bootstrap/ir/llvm-a-store-before-a-merged-store-is-ordered.t`;
an arm case in `llvm-local-on-a-hash-element-is-put-back.t`.
Probes: lo7, lr3, m1-m8, n1-n3, q2-q7 ROUNDTRIP or refused by name; no WRONG.
