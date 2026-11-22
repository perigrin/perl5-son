---
name: pending-bug-mutated-literals-keyed-by-node-id
description: "OPEN (found in wire v2 stage 9b's proof): %MUTATED_LITERALS is keyed by node id, ids are per graph (`ArrayLiteral#12`), and the table lives for a whole compilation unit -- a literal mutated in one sub marks an unrelated node of another; conservative (a pinned PostfixDeref '@' for a flattened read), never a wrong answer seen"
metadata:
  type: project
---

OPEN, found 2026-11-22 by tools/wire-braun-proof.pl over chalk's lib.

`%SoN::FromOptree::MUTATED_LITERALS` records aggregate literals mutated in
place by node id (`$node->id`), and is cleared once per compilation unit
(lib/B/SoN.pm, `_translate_program`). Node ids come from the sub's own
NodeFactory (`"${op}#${cfg_counter}"`), so two subs of one file share ids:
a literal mutated in one sub marks the node of that id in every sub after it.

What it does: the flattened-read shortcut is refused where it was safe -- a
list read becomes `PostfixDeref '@'` pinned to memory (JSON::PP::object_to_json's
`join(',', @results)`, Ref::stores_through's `grep ... @nodes`). Conservative;
no wrong answer found. What it costs: wires depend on which subs came before
in the file (the 9a and 9b wires of one sub differ by it, the counters having
moved), so per-graph comparisons across producers are noisy.

Fix when it is next in the way: key the table by `refaddr` of the node (or
by graph and id), with %MUTATED_LITERALS' forward-following (stage 9b, at
`_braun_seal`) kept. Then re-record what moves.

Related: [[a-loop-is-walked-once]].
