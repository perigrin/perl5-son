---
name: an-endless-loop-in-an-arm-lost-the-join
description: "SILENT WRONG ANSWER fixed: `if (C) {A} else { while (1) { ... last ... } } REST` walked REST as the loop arm's only; _find_join_addr's op_next scan cycled in the loop body. Found by V3 write-unreachable on chalk2 (Earley::_force). A v1 fix is listed for the downgrade proof"
metadata:
  type: project
---

Wire v2 known issue 4 (2026-11-21). chalk2's `write-unreachable` 7 was one
graph, `Chalk::Bootstrap::Earley::_force`: the reify arm's call, assign and
deref reached no Return. The arm's Region had no successor at all: what
follows the if/else (`$v->{memo} = $result; ... return $result`) was built
after the else arm's `while (true) { ... last ... }` only.

`_find_join_addr` takes the first op both arms' `op_next` chains share. A loop
left only by `last` cycles in its body and never reaches the op after it, so
no join was found and the rest was walked as that arm's. On the other path
its stores and the return were lost: `if ($h->{a}) { $r = 7 } else { while
(1) { ...; last if ... } } $h->{m} = $r` deparsed to a program printing
`undef` for perl's 7. chalk refused it for another reason; nothing caught it.
The scan now steps over a loop (`enterloop`/`enteriter` to `lastop`).
`while (C)` was fine: its chain leaves through the condition.

**The verifier's V3 found a wrong answer no gate saw.** A store no Return
reaches backwards is a dropped effect, not a counting quirk: read the graph.

**A v1 bug fix and the downgrade proof.** The fix changes v1 for that graph
on purpose (corpus and probes: none). `t/data/wire-v1-changed-on-purpose.tsv`
lists such graphs, each with its test; `tools/wire-diff.pl --allow` prints
them as `allowed`. Everything else stays byte for byte.

chalk2 `phi:memory-as-value` (25 at stage 3) was the copy of 77c664b: 0 at
the merge already.

Related: [[the-wire-verifier-and-its-ratchet]], [[a-silent-drop-is-worse-than-a-refusal]].
