---
name: pending-bug-mutated-literals-keyed-by-node-id
description: "CLOSED (branch id-collide): %MUTATED_LITERALS was keyed by node id, ids are per graph, the table per compilation unit -- one sub's mark pinned another's read; keyed by the node now (refaddr => node), and the 9b proof re-run row by row"
metadata:
  type: project
---

CLOSED 2026-11-23, branch `id-collide`. Found 2026-11-22 by
tools/wire-braun-proof.pl over chalk's lib.

`%SoN::FromOptree::MUTATED_LITERALS` recorded aggregate literals mutated in
place by `$node->id`, and lives for a compilation unit (cleared in
lib/B/SoN.pm `_translate_program`). Ids come from each sub's NodeFactory
(`"${op}#${cfg_counter}"`), so `sub a { my @a=(1,2); $a[0]=5; ... }` marked
`sub b { my @b=(1,2); join(",", @b) }`'s literal and b's join read @b through a
pinned `PostfixDeref '@'`. Conservative, no wrong answer; but a sub's wire
depended on the subs before it, and both sides of the 9b proof were noisy.

Fix: the table is `refaddr => node`. Holding the node keeps its address from
being reused while the mark stands (a refaddr-keyed table that does not hold
its key can collide the same way after a free). Test:
t/from-optree-a-mutated-literal-is-marked-in-its-own-sub.t.

The proof re-run with the fix on both sides is baseline section 19: of the
17 rows, 6 were this collision; the rest were two 9a scout marks and three
departures of Braun's scan, one of which hid a silent wrong answer.

Related: [[a-loop-is-walked-once]], [[a-proof-base-needs-the-fix-too]].
