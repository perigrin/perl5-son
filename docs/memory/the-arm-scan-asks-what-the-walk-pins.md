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

- **Run the rule on chalk's lib too; it found three more classes there.**
  (1) A FIELD stored alone in an arm (`$any = 1 if C`, `$n++ if C`, `$n +=
  2 if C` in a method): the scan knew `padsv_store` and TARGMY, the forms
  perl's peephole makes, and B::SoN suppresses the peephole. (2) `$st->{i}++`
  in two arms of one if shared ONE pinned read: the Subscript was
  hash-consed (same container, key and memory in both arms), pinned twice,
  and both stores followed it; it is `make_unique` now, as the scalar-deref
  and field forms beside it were. Any `make` followed by `_pin` is suspect
  for the same reason: `control_in` is not in the content hash. (3)
  `Chalk::Bootstrap::Perl::Actions::SubroutineDefinition`: an elsif arm
  deep in a foreach whose inner if builds control while the arm itself got
  none. NOT fixed and not reduced to a small program (six tries); the chalk
  `control-fork` row is 1 for it. chalk and the deparser both refuse such a
  graph by name ("a control node with 2 successors").
- **OPf_MOD on a pad op is not a store.** The first field fix took any field
  `padsv` with OPf_MOD as a store. perl sets that flag on a field passed to a
  sub and on one dereferenced for a write, and the existing refusal "a
  consumed value-context ternary whose arms store a class field" then fired
  on every ternary with a field in a call's arguments: 15 of chalk's lib
  graphs gone. The test reads the sassign's last child, the aassign's left
  list, the operand of an increment or an OPf_STACKED operator.
- **What caught that was `#graphs`, a number nothing held.** The re-counted
  chalk rows showed four rows FALLING between the base producer and this one
  -- good news, read alone -- and `#graphs` 24521 -> 24478. A refused sub
  takes its violations out of every row. The ratchet holds `#graphs` now, as
  it held `#wires`. Compare the graph NAMES of two wire caches before
  believing a count that fell (`scratchpad/v2s01/gnames.pl DIR1 DIR2`).
- **A fork that was a silent wrong wire is a refusal now in value
  context.** `my $n = C ? ($s =~ tr/a//) : 0`, a slice or package array
  assigned inside a consumed ternary, a field stored in one: each was a fork
  and is "a consumed ternary arm stores ..." (the existing refusals; their
  message says "an element" for all of them). Statement forms get their If.

**Not done:** the producer does not refuse a fork it builds. Stage 3's V9
("0 from stage 3") is where that becomes a hard rule; until then the ratchet
row is the guard.

Related: [[the-effect-table-is-the-one-statement]],
[[the-wire-verifier-and-its-ratchet]], [[one-constructor-places-every-node]].
