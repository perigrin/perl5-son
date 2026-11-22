---
name: a-loop-goes-round-by-an-edge
description: "Wire v2 stage 9a: a Loop is [entry, back] and its test an If; what the flip taught -- chalk writes wires too, If carries control twice, a pass that always returns has no way round, a write-back that returned early"
metadata:
  type: project
---

Wire v2 stage 9a (branches `v2-s9`, 2026-11-22). Profile
`["mem","eval","loop"]`. Every loop translator builds its test as
`If [C, cond]` on the control the pass has reached -- the Loop, or the
condition's last pinned effect (`while (my $n = shift @w)`: the shift) --
with Proj 0 the body and Proj 1 the way out (`_loop_test_if`), and sets the
Loop's second input to the control the pass ends at (`_set_loop_back`): the
body's end, the latch Region of the `next`s, the spin's Proj 0, the computed
goto's Proj 1. The serializer cuts `Loop.inputs[1]` from the order (the
second sanctioned forward reference) and writes no `control_in` on a Loop.
chalk's loader defers it like a loop Phi's back edge (L8); T2 finds the test
as the If the Loop's chain comes to through pinned nodes -- and through a
branch of the condition (`while ($n && f($n))`: the && If and its Region) --
whose Proj 1 is a way into the exit Region the Loop heads.

**Lessons:**

- **chalk writes wires too.** `Chalk::Regex::Graph` builds each constant
  regex's matcher as a wire with loops in it; deleting T2's old loop path
  turned 15 SAME probes REFUSED that had no loop in their source (al10's
  `s/a/Z/`). Grep the consumer for its own producers before a flip.
- **An If carries its control twice** (`inputs[0]` and `control_in`): a walk
  that collects successors from both sees the If twice. V11's count and
  `as_v1`'s chain both had to dedupe; as_v1's miss sent the deparser into an
  endless recursion (corpus 113, out of memory), not a refusal.
- **A pass that always returns has no way round** (Carp's `for ($x) {
  return ... }`): the back input would be the return's control, which also
  enters the sub's exit -- a control fork. The Loop keeps one input and its
  Phis are forwarded to their inits (`_one_way_loop`); chalk refuses it by
  name. as_v1 gives the deparser v1's two-input Phis back (init twice).
- **A write-back that returned early left a loop with no way round or out**
  (al1, al2: `for my $y ($x) { $y = 5 }`): the iterator over a scalar source
  rebound the scalar and returned before the back edges and the exit Region;
  the code after the loop hung off its body. Now the scalar is carried on a
  loop Phi and the loop leaves by its exit; the phi-arity rows went to 0 (T2
  still refuses both, on the list's PadAccess).
- **A test that writes only its own `while` shape is ambiguous with a guard**
  -- `while (1) { last unless C; ... }` is an If whose Proj 1 leaves; read as
  the test it is the same program, so T2 and as_v1 may take it as one.
- **Measure the deparser on as_v1 too**: the round trip (430) is the
  adapter's test; every new wire shape needs its v1 spelling there.

Related: [[an-eval-s-die-has-its-way-out]], [[the-loader-holds-v2-to-its-invariant]],
[[the-deparser-reads-v2-through-as-v1]].
