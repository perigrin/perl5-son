---
name: the-arm-scan-asks-what-the-walk-pins
description: "Wire v2 stage 1a: `if (C) { bless $o, 'X' }` got its If back by the arm scans asking B::SoN::EffectTable::on_chain; the verifier's new control-fork rule then found six more statements with the same hole ($#a = N, tr///, slice assigns, package aggregates, mixed list assigns). A rule finds a class; a probe finds a case"
metadata:
  type: project
---

Fix for [[a-bless-only-arm-loses-its-if]] (probe cr8), branch `v2-s01`,
2026-11-20.

**What was wrong.** "Does this arm need control flow?" is answered before
the arm is walked, by scanning its ops (`_arm_has_void_call`,
`_arm_has_element_store`, `_arm_advances_control`, ...). What the walk then
PINS is decided elsewhere (`_pin` / `_place`, the effect table). A statement
the walk pins and the scan does not know gets no If: it follows the control
before the test, beside the next statement, and RUNS WHETHER OR NOT THE
CONDITION HOLDS. bless was added to the effect table and not to the scan's
list.

**What changed.**

- Both scans ask `B::SoN::EffectTable::on_chain($op->name)`. `%EFFECT_OP`
  keeps only what the table does not pin in every context (push, pop, shift,
  unshift, splice, delete).
- `SoN::Verify` has `control-fork` (the plan's V9): a node other than an If
  or a Loop with more than one control successor. Baseline 0 for corpus and
  probes, held by the ratchet.
- `_op_places_a_store` names the stores the rule then found (below).

**Lessons:**

- **The rule found six more in an hour; the probe had found one in a
  month.** With `control-fork` written, a file of 100 one-statement arms
  (`if (@ARGV) { X } print ...`) through it showed: `$#a = N` (and perl's own
  Carp::caller_info has that arm: three corpus wires carried the fork),
  `$s =~ tr/a/b/`, `@a[0,1] = ...`, `@h{...} = ...`, `our @g; @g = ()`,
  `@$r = ()`, `($x, @r) = LIST`. Every one executed unconditionally on the
  wire. None was in the corpus's own programs or the 486 probes.
- **`_op_places_a_store` is still a list.** It is the same kind of thing that
  lost the bless. What holds it is the checker, not the list's completeness:
  a new pinned store with no arm predicate shows up as a `control-fork` row
  above 0. The scratch files are worth re-running after any new `_place`
  site: `scratchpad/v2s01/arms.txt`, `arms2.txt` with `forks.pl` (one
  program per line; prints FORK / ok / GAP).
- **chalk needed nothing** for any of these: an If whose arm is one pinned
  node lowers today. cr8 turned SAME; the six others are SAME through chalk.
- **The op that writes is not always the op that is flagged.** `$#a = 0` is
  `sassign` over `av2arylen` with OPf_MOD; a whole assign to a package array
  is `aassign` whose left side holds an `rv2av` (`_stash_target_sigil` finds
  it); a `my` array among several targets is `padav` under the aassign's
  left list. A sole `my` aggregate target is a REBINDING, merged as a value
  with no control, and must not be given an If for nothing.

**Not done:** the producer does not refuse a fork it builds. Stage 3's V9
("0 from stage 3") is where that becomes a hard rule; until then the ratchet
row is the guard.

Related: [[the-effect-table-is-the-one-statement]],
[[the-wire-verifier-and-its-ratchet]], [[one-constructor-places-every-node]].
