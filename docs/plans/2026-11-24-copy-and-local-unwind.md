# Designs A and B -- approved by perigrin 2026-11-24: A = always copy; B = B1 (one edge per may-die point)

# Two design proposals: class A (hash copies) and class B (a fault under a `local`)

Heads read: producer `/home/user/repo` (reaudit-refuse) and chalk `/home/perigrin/dev/chalk` at 890c0ff8.

---

## Design A: a copy of a `my` aggregate is a new location

**Model change.** Today a `my` aggregate's literal node is its location, and the walk can bind a second name to that same node. So `my %c = %h` makes `%c` the same location as `%h` (re-audit section 4, the first Click departure). The rule becomes: lexical storage is an environment that maps a name to a location, and `=` always makes a new location. Two names share a location only through an explicit alias: a foreach alias, `@_`, a refalias, or a glob assignment. Globs are in the package environment and are already a typed binding.

In Click's terms, the literal is an allocation, which has identity, and a copy is a new allocation filled from a read of the source at a version (memory SSA). Binding the copy to the source's node is copy elision, as in scalar replacement of aggregates. That is sound only when neither side is stored to after the copy. The producer's proof of "not stored to" is a syntactic scan (`$MUTATED_SLOTS` and `$HASH_WRITTEN`), and class A is that scan's holes. Arrays already always copy. Hashes would too.

**Wire changes.** None are required. Two are optional and each needs your approval:
- **(WIRE, optional)** A `my` aggregate literal that is stored into gets `mem_out`: an allocation is a version, as `MakeCell` already is.
- **(WIRE, optional)** A place `Subscript` carries the name the program wrote through. With that, `SoN::Verify` can check that a store's root literal belongs to the same name. Section 21 notes the verifier cannot see class A today.

**Producer changes** (`/home/user/repo/lib/SoN/FromOptree.pm`).
- In the aassign handler (`:12190-12199`), delete the GAP. Any `%c = %h` whose source is a named `HashLiteral` goes the way a written source already goes: a new `HashLiteral` (symbol `c`) whose input is the source, pinned where the copy is made (`$copies_written_hash`, `:12181`, and `:12320-12334`).
- `_copies_written_pad_hash` (`:20456`) stops asking whether anything writes the hash. A package target (`our %P = %h`) stores that new literal too, not the source node.
- Add a producer assertion in `_place`, with no wire change: a store's root literal must be the pad slot of the op's own target. Otherwise it dies with a GAP, which makes the bug class loud.
- Probe every aggregate kind (`my`, package, shared, field, in a loop, in a sub), following the re-audit lesson "arrays were right, hashes were not".

**Chalk changes.** Probably none. A `HashLiteral` built from another hash literal is already lowered: `my %g = %h; $h{a} = 5` is SAME. The interval oracle will need re-keying, because node ids move.

**Lifts.** All 26 rows that say `a copy of a hash that may then be written`: rej25, rek01/03/04/05/08/09/13/14/16/17/19/20, rem19, ren07/09/10/22-27/29/30/35.

**Risks and open questions.**
- Copies that were elided now cost a real copy when the program runs. This is a speed cost only, not a correctness one. Chalk can win it back later as an optimisation based on memory SSA.
- **Open question:** keep elision in the producer when the scan says neither side is written? I recommend no. Always copy, which is sound by construction, and measure the census and the corpus gate.
- The copy is shallow, as in perl (m19 and n24 share their inner references). Check that with the probes.

**Size.** S. About 30 producer lines plus tests, about 1 day. Add about 1 more day for each optional wire addition, if approved.

---

## Design B: a sub's faults have a way out that restores its `local`s

**Model change.** In C2 and Graal every method has an unwind path (Graal: `InvokeWithException` and `UnwindNode`; LLVM: `invoke` plus a cleanup landing pad). Here only an eval has one. The new rule: wherever something may die, a `local` of this graph is live, and no eval of this graph is open, that point gets an exceptional way out that carries the restores. This covers sub calls, `Unwind`, a `Divide` or `Modulo` that may fault, and a dereference that may die. A die of the sub's own already restores before its `Unwind` (`_pin_die`, `:6281`). A point with no live `local` needs no edge, and chalk keeps its default unwind there. The same edges are where `finally` and `defer` (class C) would later go: the re-audit's "one class" lesson.

**Option B1: one edge per may-die point.** This is the plan's Q9 "rethrow pad": `Exc [T]`, then the restores of the `local`s live at T (as `_exc_edge`, `:6256`, builds them), then an `Unwind` with `fields.rethrow`. Every edge is static and exact, and it is the `eval` profile's shape minus the catch.

**Option B2: one exceptional exit per sub.** All edges meet at one unwind Region with a memory Phi and one rethrow. Each point has a different set of live `local`s, so the restores cannot simply stand after the merge. They can either:
- stay on each edge, in which case the merge buys nothing but one `Unwind`; or
- stand once after the merge, each guarded by a per-local "made" Phi and an `If` (perl's savestack done statically; Braun-style Phis at the exit).

  An unguarded "restore to the current value" is not a no-op: a tied or magic variable sees the write, and `local $h{k}` restores by delete-or-upsert.

  B2 is O(points + locals) nodes against B1's O(points × locals). It needs a Region with no `eval_id`, which breaks loader invariant L7 and verifier rule V10 as written, and chalk needs a real merge (`merge_at`, `_common_memo`).

**Recommendation: B1.** It reuses the producer's `_exc_edge` and chalk's `exc_block` almost unchanged. Merge edges whose live-local set and memory are identical only if the node count on chalk's lib calls for it (plan section 9.1).

**Wire changes (WIRE, need approval).**
1. An `Exc` may stand outside an eval body. Today V10 and L7 tie each `Exc` to an eval's catch.
2. `Unwind` gets `fields.rethrow: true`, with the `Exc` as its input. Its `mem_in` is the last restore, and it is a V3 root, like `Return`.

**Producer changes.**
- At sub entry, push a "sub frame" on `@EXC_FRAMES` with base 0 and no `eval_id`.
- `_exc_edge` takes that frame when no eval frame of this graph is open and saves are live.
- The edge ends in a pinned rethrow `Unwind`. `_pin`'s `_dies_by_its_values` check and `_call_memory_barrier` already call `_exc_edge`.
- V10 grows "may die under a live local, outside an eval, so it has an edge". Mutation-test it.
- The deparser's `as_v1` drops these edges, as it drops `Exc` today.

**Chalk changes.**
- In `after_call`'s branch for a sub with no open eval (`Builder/Calls.pm:29-44`): if the statement has an `Exc`, branch to its block, walk the restores, then `ret undef` with the dying flag still set.
- The same applies to `Unwind` with `rethrow` (`Control.pm` near `:472`).
- Delete W6, `_calls_a_local_dies_through` (`Serialize/WireCheck.pm:211-240`), and the `check` line that calls it.
- WireInvariant L7: an `Exc` outside an eval must lead to a rethrow `Unwind`.

**Lifts.** All 24 W6 rows in `BASELINE.tsv`:
- class B (reb33, rec01, rec09, rec11-13, rec15, rec17-20, req32, req34, req36-39);
- r/c02 and r/c03, back to SAME;
- the call case Q9 left refused (aun70, reb02, rec04, rec06, req35).

**Risks and open questions.**
- Chalk inlines some callees. An inlined callee's rethrow must branch to the caller's way out, not `ret`.
- `has_eval` gates `after_call`. If the program has no eval, `local`s restored on a fault matter only to END blocks, which perl runs after unwinding. Refuse that case or handle it?
- Graph size on chalk's lib, which uses many `local $b->{...}` around calls. Measure it.
- The interval oracle is re-keyed again.

**Size.** B1 is M: producer about 2 days, chalk about 2 days, verifier and invariant about 1 day. B2 is L.

---

### Critical Files for Implementation
- /home/user/repo/lib/SoN/FromOptree.pm (aassign `:12150-12335`, `_pin` `:889`, `_exc_edge` / `_pin_die` / `_catch_way` `:6242-6320`, `_copies_written_pad_hash` `:20456`)
- /home/user/repo/lib/SoN/Verify.pm (V10 `:468-520`, V3 roots)
- /home/perigrin/dev/chalk/lib/Chalk/Target/LLVM/Builder/Calls.pm (`after_call` `:29`)
- /home/perigrin/dev/chalk/lib/Chalk/Target/LLVM/Builder/Control.pm (`exc_block` `:525`, the die branch for a sub with no open eval `:472`)
- /home/perigrin/dev/chalk/lib/Chalk/IR/Serialize/WireCheck.pm (W6 `:211-240`) and `WireInvariant.pm` (L7)