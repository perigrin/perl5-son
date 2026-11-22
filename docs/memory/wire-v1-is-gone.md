---
name: wire-v1-is-gone
description: "Wire v2 stage 6: B::SoN writes v2 only, chalk reads v2 only; what deleting v1 and its guards exposed -- a refusal that hid a silent wrong answer, upgraded fixtures with forward memory edges, an oracle named by node ids, a rule the probes still need"
metadata:
  type: project
---

Wire v2 stage 6 (branches `v2-s6`, 2026-11-21). B::SoN writes v2 only
(`wire=2` names it, any other `wire=` is refused by name); SoN::Verify
checks v2 only; chalk's loader refuses any other version (`GAP: wire version
1`), and a `mem_in` naming a node listed after it. Deleted: the v1 writer,
the v1 verifier rules, chalk's WireUpgrade, `Phi::is_memory`,
`Assign::is_placed`, WireCheck's `_floating_effects` and
`_floating_divisions`. `SoN::Wire::as_v1` stays for the deparser (stage 11).

**Lessons:**

- **A refusal can hide a wrong answer it was not written for.**
  `Assign::is_placed` refused a list assign into an aggregate whose readers
  did not all come after it. Deleted (the plan: L5 makes it pointless),
  `my ($x, @r); ($x, @r) = g(); print "$x"; ($x, @r) = (4, 5); print "$x"`
  printed `1` twice: B::SoN reads a declared-earlier `my` scalar a list
  assign rebinds by name -- one PadAccess node, no memory version -- so T2
  makes `"$x|"` once. With no aggregate beside it, the same program was
  already WRONG at base (`1 2 1 2` for `1 2 3 4`); the probes and the census
  had neither. Before deleting a guard, run the shapes it refused with one
  more write and read interleaved, not only the probes. Refused by name now
  (Lower.pm: `a my scalar two list assignments bind one after the other`);
  the producer fix (reads at a version) is stage 7's class.
- **Decide a refusal on the graph, not on T2's lowering state.** The first
  guard asked T2 "was this target read before?" -- T2 marks a value made in
  any scope, so an if/else binding the scalar in each arm (corpus 165) was
  refused, and only the gates' t2-census-cases.t saw it. The graph says it:
  one list assign control reaches from the other.
  It refuses fk7 (right: `$x` bound in two ifs, read after the second only);
  fk7 was REFUSED at the stage's start too, by is_placed.
- **Delete a covered rule by turning it off and running the probes.** With
  `_floating_effects` and `_floating_divisions` off nothing changed; with
  `_flattened_package_aggregates` off nv1 nv4 nv5 nv7 nv8 lo14 went WRONG
  (W10: a package aggregate flattened at no version). It stays until stage 7.
- **An upgraded v1 wire has forward memory edges**: a node on the chain
  named a merge's memory Phi the wire listed after it. B::SoN's v2 never
  does, so the loader refuses one now -- and the v1 fixtures converted once
  by the upgrader had to be renumbered (memory before its users) too.
- **`grep { defined } $h->{k}, ...` autovivifies `$h->{k}`** (grep aliases
  `$_`): the converter wrote `"mem_in": null` into every node until the
  keys were tested by name (`grep { defined $n->{$_} } qw(...)`).
- **An oracle named by node ids moves with the wire.** The intervals oracle
  keys a node by its structural id (`Phi#36`); v2 renumbers. Re-recorded,
  then compared with the old record modulo ids: 437 of 438 cases equal; one
  (own:edges) recorded fewer proofs, which were the old record's allowed
  losses -- that case's rows kept as they were. Compare before re-recording.
- **A test can pass by hash order.** `my ($read) = grep {...} values %n`
  picked one of two reads of `$y`; v2 left an unread one at MemStart, and
  the test failed one run in three. t/oracle-mutation-precision.t merged
  every graph's nodes into one map by id: v2's MemStart moved a sub's ids
  and the Print's input was another graph's node one run in two (only the
  gates' suite saw it). Ids are per graph.
- **The downgrade proof has nothing left to compare** once the v1 writer is
  gone. The ratchet gate runs the deparser's round trip instead
  (`tools/corpus-roundtrip.pl` through `as_v1`, ROUNDTRIP >= 430 as the last
  v1 commit measured; it was 430 after the flip).

**L5 hard, and where it bends.** A non-record Assign has control_in, mem_in,
mem_out. 167/168's `($lo, $used) = g()` after `my ($lo, $used)` was pinned
and followed memory but was no version: it fills the slots, so it is
`_place`d now. The :lvalue call of 398 stays a place (the plan's 3.3): off
both chains, its one use the target of the Assign that stores through it and
calls it; that Assign is the version.

Related: [[the-loader-holds-v2-to-its-invariant]], [[the-deparser-reads-v2-through-as-v1]],
[[a-list-assign-into-an-aggregate-is-placed-or-refused]].
