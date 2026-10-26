---
name: session-bugs-loop-store-and-closure-op-assign
description: Two more SILENT WRONG answers this session's lowerings let through, found by shape-variation probe sweeps (not the census): an element store in a loop arm went to a per-pass copy of the aggregate; a closure's `$t += 1` never wrote $t (a producer shape chalk lowered)
metadata:
  type: project
---

**1. A store in a loop arm went to a copy.** `my @o = (0); for (...) {
next if ...; $o[0] += 1 } print $o[0]` printed 0 (perl 2); also `%o`, an
if/else arm, a `while`, inside a sub. Refused at the baseline.
- Why: `my @o = (0)` is an UNPINNED literal. Nothing lowered it before
  the loop; an arm's store pre-lowered its container (`_prelower_branch_
  store_operands`) INSIDE the body, so each pass built a fresh @o.
- Fix: `_prelower_aggregates_before($loop)` in the preheader lowers each
  Array/Hash-stamped unpinned literal an element store writes through,
  when its contents are already known (constants, lowered values, pure
  ops). NOT an ArrayRef/HashRef (`push @r, [0]` must be new each pass) and
  NOT a loop's seed: the first cut hoisted grep's empty collector in
  `my @p = grep {...}` inside a loop and pvm 159 went DIFFERS -- the
  census caught that one. A literal pinned inside the loop is its own.

**2. A closure op-assigning a capture.** `my $t = 0; my $f = sub { $t +=
1 }; $f->(); print $t` printed 0 (perl 1). PRODUCER BUG: B::SoN emits
`Coerce(CellParam, Ref->Num) + 1` -- the cell's reference read as a
number, no CellWrite (a plain read is CellRead; `$t = 5` is a CellWrite,
which chalk refuses). chalk lowered the odd shape. Now `_bind_captures`
refuses a CellParam reaching anything but CellRead/CellWrite/MakeCell.
Producer fix (perl5-son, not done): an op-assign to a captured lexical
should be CellRead -> op -> CellWrite.

**Lesson (third and fourth such bug this session):** every refusal turned
into a lowering widens what can go silently wrong, and the corpus covers
a sliver of the shapes. After each cause, sweep ~20 one-line probes that
VARY THE SHAPE around what now works (inside a sub, with next/last, under
an if/else, a while, a closure, a hash instead of an array) and treat any
WRONG as a stop-the-line bug. The sweeps live in the scratchpad's
allprobes.txt, swept by check.sh.
