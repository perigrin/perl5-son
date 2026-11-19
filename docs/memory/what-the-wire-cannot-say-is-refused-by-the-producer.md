---
name: what-the-wire-cannot-say-is-refused-by-the-producer
description: "vp5 (an element operand read by alias then stored) and fl14 (use warnings FATAL) have wires identical to right programs; the producer refuses both by name. Why vp5 is not re-read; where FATAL bits are"
metadata:
  type: project
---

Two of the three probes chalk's WireCheck could not split (2026-11-19).
Their wires say nothing wrong, so no consumer rule can refuse them; the
producer is the only place that still has the optree.

**vp5: `$a[0] + ($a[0] = 10) + $a[0]` is 30 in perl.** `$a[0]` is pushed as
the element, and `+` reads it when `+` runs. The wire read it where its op
stood: 1 + 10 + 10. `_reread_alias_operand_stored_later` -- the walk that
already re-reads a lexical operand a later operand stores -- now dies when an
operand is an element read and a later sibling holds an lvalue element of
the same container.

- NOT re-read after the store, as a lexical is: an element is an alias only
  if it existed when read. `$h{new} . ($h{new} = "q")` pushes undef and reads
  "". The walk cannot know which.
- The container is named from the optree: `$a[`, `$h{`, `$r->[`.
- A value computed from the element (`($a[0] + 1) + ($a[0] = 10)`) is a copy
  and lowers. So does `$a[0] = $a[1]` (an assignment's own target is not a
  later operand: sassign's and a storing multiconcat's last kid) and
  `$_[0][$_[1]] = ...` (`$_[0]` is OPf_MOD with OPpDEREF: vivified, not
  stored).
- ponytail: two references to one array are two containers to this check.
  A call in a later operand that stores the element is not seen either.

**What went wrong on the way, each found by the suite, not the probes:**

- **The sim's stack is not the current expression's operands.** My first
  version scanned the stack for a Subscript read at each element store. A
  statement's value stays on the stack after the statement, so `my $x =
  $a[0]; $a[0] = 99` was refused. Ask the optree which operands are pending.
- **B::SoN compiles with the peephole off.** `perl -MO=Concise` showed
  `aelemfast_lex` and `multideref`; the walk sees `aelem(padav, const)`.
  Write optree checks against what a `warn $op->name` in the walk prints.
- **OPf_MOD is not "stored".** An element dereferenced on the way to a store
  carries it too.

**fl14: `use warnings FATAL => "all"` turns `"abc" + 1` into a die.** The
bits are on the statement's COP and reach no node. `_refuse_fatal_warnings`
scans a CV's nextstates: `$cop->warnings` is a B::SPECIAL for perl's three
shared sets (all, none, default) and a string otherwise, two bits a
category, the odd one FATAL. Any odd bit set refuses the graph.

- A BEGIN block is exempt: it has run. Without that, `no warnings FATAL =>
  "all"` (compiled under FATAL) was a skipped BEGIN.
- chalk's lib and the corpus have no FATAL warnings; nothing was lost.

**Lesson:** "refused by name" is a producer fix when the missing fact is in
the optree and the wire has nowhere to put it. Say in the message what the
wire lacks (a control edge for the fault; place versus value).

Related: [[the-wire-is-checked-before-it-is-loaded]],
[[a-silent-drop-is-worse-than-a-refusal]].
