---
name: the-wire-names-its-memory-edges
description: "Wire v2 stage 3: the producer writes v2 behind wire=2 (mem_in, mem_out, record, version, profile); memory operands live in mem_in, a v1 writer puts them back; proved byte-identical against the commit before; SoN::Verify's v2 rules; what the counts say"
metadata:
  type: project
---

Wire v2 plan, stage 3 (branch `v2-s3`, 2026-11-20).
`perl -MO=SoN,json,wire=2` writes v2 (`version: 2`, `profile: ["mem"]`); the
default is still v1, byte for byte.

**How the IR carries memory now.**

- `SoN::IR::Node` has `mem_in`, `mem_out`, `mem_operand`. `make(..., mem =>
  $sim->memory)` is a read of memory where it is built: part of the content
  hash (appended where v1's trailing input was, so ids are unchanged), and a
  consumer edge registered after the inputs (so consumer order, and with it
  the serializer's walk order, is unchanged). `_pin` gives `mem_in` to a node
  that touches memory (`touches_memory`, by kind) or is about to be a version;
  `_place` and `_call_memory_barrier` set `mem_out`. Nothing else may make a
  node the sim's memory (t/placement-one-constructor.t).
- `inputs` are values only. `v1_inputs` is the old list, memory last: the
  walker's own questions (a Subscript of two inputs is a place, the last input
  of a pinned read is the memory before it) still read it. Retire it question
  by question; it goes with v1.
- The v1 writer emits `inputs` + `mem_in` when `mem_operand`, and
  `memory_input` on such a Call. It leaves out a node marked `v2_only`: the
  memory Phi where a sub's exits merge, which only a v2 Return names.
- `record` is written for an Assign on neither chain. It is derived at the
  writer, not set where the Assign is built (the plan's wording): an Assign
  left off the chain by mistake is then a `record` that V7 rejects by its
  targets, which is where the floating stores of v1 now show.

**The proof** is t/wire-v2-downgrades-to-v1.t (and `tools/gates.sh`'s
`downgrade` gate over everything): each wire compiled by the commit before
and by this tree, compared graph by graph (`tools/wire-diff.pl`).

**Lessons:**

- **A writer-side flag beats a kind table for the downgrade.** The plan
  proposed putting `mem_in` back by `%MEM_MIN_INPUTS`; RegexSubst and
  Transliterate have optional operands the table cannot locate. The node
  knows whether its memory was an operand; the writer asks it.
- **Iterating a copy and writing into it loses the write.** Two B::SoN passes
  took `my $inputs = $node->inputs` and assigned coercions into it; switched to
  `v1_inputs` (a copy) they changed nothing, and the sample proof showed it at
  once (36 of 60 graphs). A pass that writes inputs reads `inputs`.
- **Compare wires under one root.** A probe's wire names its file; two
  checkouts give two paths and every probe "differs". tools/wire-diff.pl
  normalises them.
- **A big chalk wire times out under load.** wire-verify.pl's 300 s limit
  leaves Target/LLVM and Lower empty when other jobs share the machine; the
  diff reports them as "wire only in OLD", not as equal.

Related: [[one-constructor-places-every-node]], [[the-wire-verifier-and-its-ratchet]],
[[the-arm-scan-asks-what-the-walk-pins]].
