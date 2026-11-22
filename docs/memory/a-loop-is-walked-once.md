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
  the pads under a substitution's subject, an element's container under an
  assignment's target (`($a[0], $a[1]) = ...` in a loop flattened @a's
  literal after it: `1 2` for `4 5`, found by chalk's suite, not by the
  proof's sets). A `my $s` the pass declares stays in (a C-style for's
  `my $j` keeps its binding past its block); a `my @a`/`my %h` is out -- a
  fresh aggregate each pass (chalk's LR0DFA `my %kernels`). 484 corpus+probe loops: 507 extra Phis
  -> 23, no miss.
- **A refusal that hangs on what the loop carries waits for the sealing.**
  `$h{$k} //= []` into an aggregate the loop rebinds is refused (GAP); read
  off the header's incomplete Phi, it refused LR0DFA's and Earley's loops,
  where the Phi was trivial. The walk records it on the key
  (`refuse_if_carried`), `_braun_seal` dies with it only for a Phi that stays
  (t/loop-a-hash-the-pass-declares-is-not-carried.t).
- **The proof over chalk's lib does not close** (17 rows, 10 graphs; five read
  node by node, the other five differ by a `PostfixDeref '@'` and its users
  alone): the 9a wire there carried the scouts' doing -- a
  `mutated_aggregate` set by a scout before the real walk (Builder::_common_memo:
  a copy versioned at the pre-loop memory), node-id collisions in
  `%MUTATED_LITERALS` that moved with the counters (a pinned
  `PostfixDeref '@'` on one side: object_to_json's `join(',', @results)`;
  [[pending-bug-mutated-literals-keyed-by-node-id]]), and a `my @a` with no
  Phi now lowered as a TernaryExpr where 9a built an If (check_nodes'
  `@controls = ... if ...`). No WRONG in probes, census or the deparser's
  round trip; corpus and probes are SAME up to the listed stamps.
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
