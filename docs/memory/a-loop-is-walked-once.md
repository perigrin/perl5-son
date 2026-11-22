---
name: a-loop-is-walked-once
description: "Wire v2 stage 9b: Braun's construction replaced the scouts -- a header of incomplete Phis from a scan of what rebinds a slot, sealing forwards the trivial ones, a wrong guess is learned and the sub walked again; what the walk reads by a binding's class is what the scan must leave out"
metadata:
  type: project
---

Wire v2 stage 9b (branches `v2-s9`, 2026-11-22). A loop's header is built
before its body is walked: an incomplete Phi for every slot the body may
rebind (`_may_write_targs`) and one for memory (every loop, `_braun_mem_phi`).
The body is walked once. At sealing (`_braun_seal`) each Phi gets its back
input, and one the pass never wrote is forwarded to its init
(`Phi::set_forward`; the serializer writes the init where it is named and
`Graph::nodes` leaves it out; V8 `phi-trivial` holds it at 0). What the walk
guessed is checked there -- a slot the scan missed, a stamp the back edge
loses, whether the body writes its iterator (`_writes_guess`) -- and a wrong
guess is learned (`%LOOP_HINTS`, by the loop's first op) and the sub
translated again (`_translate_from`). Depth 14: 28 s -> well under 2 s.

**Lessons:**

- **The walk reads a binding's class, so a Phi is not free.** The plan
  expected an over-approximated slot to cost one trivial Phi. It cost wrong
  wires: an incomplete Phi where a literal stood lost its element stamp
  (`$a[0] += $n`), turned a known closure call indirect (`$add->($x)`),
  made `(my $b = $raw) =~ s///` substitute into $raw (a silent wrong the
  deparser round trip caught), and refused foreach loops by the class of the
  list. So the scan asks what REBINDS a slot, not what changes it: not an
  element's container, an aggregate a builtin changes in place, a call's
  argument, a deref's operand, a foreach's list, a `my` the pass declares,
  the pads under a substitution's subject. 482 corpus+probe loops: 507 extra
  Phis -> 63, no miss.
- **A mark on a node the walk made is lost when the node is forwarded.** An
  inner foreach writing @b's elements marked the outer loop's Phi for @b
  mutated; forwarded, the read after the loops flattened the literal (`5 6`
  for `5z 6z`). `%MUTATED_LITERALS` follows the forward now. Look for every
  table keyed by a node the walk may forward.
- **Merges compare what a node stands for** (`->resolved`): StackSim's
  merges and the break exits; a forwarded Phi on one arm and its init on the
  other is no merge.
- **A wrong guess must not refuse before it is checked.** The iterator-write
  guess decides refusals before the walk (`a foreach whose body writes its
  alias and may reshape the array`); a guess from OPf_MOD alone (sprintf's
  list, `\$x`, `$i->@*` as a foreach's list) refused graphs the scouts let
  through. The guess reads the lvalue's parent; retrying with the other
  answer on any death was tried and dropped -- it turned refusals by name
  into graphs.
- **A dirty walk goes on to its end.** Stopping at the first wrong guess cost
  one walk per nesting level (an inner Phi unstamped unstamps the outer's
  back edge); the walk that guessed wrong finishes, unstamping as it learns,
  and the nest learns in one walk.
- **The scouts' imprecision was in the 9a wire too.** Placeholders for every
  slot left Phis unstamped (lp12, lp28), an eval numbered twice (ev5: 2 for
  1), a line left behind (Carp::trusts: 722 for 715), and a graph refused for
  a scout's dead node that may die (ev8, now SAME). The proof
  (tools/wire-braun-proof.pl) lists those apart: SAME-BUT-STAMPS, GAINED.
- **The scouts were the Lower.pm two shapes.** chalk's Lower.pm under the
  9a producer: two wires by hash seed (go_round refused one way or the
  other); under 9b, six seeds, one wire. The pending note is closed.
- **A condition's writes are read where the walk first meets an and/or**
  (Phase 4b): the scout's probe did that, and `while (1) { $x++; last if C }`
  needs it (else an exit Phi of one input the deparser cannot spell).
- **Do not edit lib/ while a suite or a proof compiles from it**: results mix
  two producers; and the corpus cases must sit at one path across runs (a
  wire names its file).

Related: [[a-loop-goes-round-by-an-edge]], [[a-new-binding-can-refreeze-a-loop]],
[[a-written-package-scalar-is-never-carried]].
