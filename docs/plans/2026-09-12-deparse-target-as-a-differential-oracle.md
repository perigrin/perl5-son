# A deparse target as a differential oracle

**Date:** 2026-09-12
**Status:** PROPOSED. Not started. Written for review before any code.

## The problem this solves

Every correctness check on the producer today is STRUCTURAL: read the emitted
graph, reason about whether it says what perl says. That is how this session
found its defects, and the record shows what that method is bad at.

| Defect | How found | Class |
|---|---|---|
| `sort bylen (...)` sorted 4 items, perl sorts 3 | reading the graph | wrong answer |
| stacked sort claimed `sort_cmp: string` for a numeric descending comparator | reading the graph | wrong answer |
| `@$r` substituted construction-time elements, losing mutations | reading the graph | wrong answer |
| `push @$r` took the flattened elements as operands | reading the graph | wrong answer |
| `keys`/`values`/`each` do not observe stores | noticed BESIDE other work | wrong answer |
| nested one-armed element store: memory-Phi dead | reading the graph | wrong answer |

Every one is a WRONG ANSWER from a structurally plausible graph. None was
caught by the test suite, which was green throughout. They were caught by
inspection, which only finds what the reader thinks to look at -- the
`keys`/`values`/`each` defect was found by accident while checking something
else, and is still open.

A differential oracle catches this whole class mechanically: run the original
under perl, run the graph's rendering, diff. See
[[read-generated-output-not-tests]] -- this is that discipline automated.

## The proposal

Emit PERL SOURCE from a SoN graph. Not an optree.

`B::` is introspection-only, so building real ops means XS (`newBINOP` and
friends) -- weeks of work, and a segfault surface. Emitting source costs a
fraction of that and buys the same differential signal, because the comparison
is `perl original.pl` vs `perl emitted.pl`, and perl compiles the emitted source
with the same front end either way.

It also doubles as a legibility check on the IR: a graph that cannot be
deparsed is usually one whose meaning is not fully pinned down.

An optree target remains possible later; nothing here forecloses it.

## Why the graph shape makes this tractable

Measured: `control_in` is a TOTAL ORDER over effects, and pure values hang off
it as a DAG.

    my $a = 1; my $b = $a + 2; print "$b\n"; print "second\n";
      9 Print  ctl<-0
     10 Print  ctl<-9
     11 Return ctl<-10

So the emitter is: walk the control chain, and for each effect emit its operand
tree as an expression. No scheduling algorithm, no GCM. That is the single
biggest reason this is a week and not a quarter.

## Vocabulary to cover

Measured over base+comp (33 files translating, 29 CLEAN): **67 distinct ops**,
steeply distributed.

Top of the distribution (each >100 occurrences):

    Constant 2607   Concat 982   Proj 889   Coerce 881   Print 836
    Region 767      Call 751     Phi 477    If 384       Add 264
    EntryWrite 242  Subscript 216  TernaryExpr 213  Return 204  Start 200
    PadAccess 198   EntryDef 192   StrEq 174  MemStart 126  And 118
    ArgsSource 117

The tail is mostly one-line binops (`Multiply`, `BitOr`, `NumLe`, `RightShift`,
...) -- cheap.

The genuinely hard set is small and known:

  - **Control**: `If` / `Proj` / `Region` / `Loop` -- reconstruct `if`/`else`
    and loop syntax from the CFG.
  - **Memory**: `MemStart` / `EntryWrite` / `Assign` / `Delete` / memory-`Phi` --
    these ARE the defect class the oracle exists to catch, so they must be
    emitted with real ordering.
  - **Ours, not perl's**: `EntryDef`, `CellRead`/`CellWrite`/`CellParam`,
    `MakeCell`, `Coerce`, `Count`, `RegexSubstCount`, `ArgsSource`. Vocabulary
    chosen BECAUSE the optree does not express it directly; each needs a
    deliberate spelling.

## The failure mode to design against

**A shared assumption cancels out.** If the emitter reproduces a fold the
walker made, the round-trip agrees with itself and the miscompile stays
invisible. `@$r` is the exact shape to fear: flatten on the way in, flatten on
the way out, output matches, bug survives.

Rule: **the emitter is deliberately dumb.** It emits what the node SAYS, never
what the source probably meant. A `Subscript` with a memory input emits an
element read at that point in the order; it never reconstructs a literal. If
that produces ugly Perl, good -- ugly and faithful is the product.

Corollary: the emitter must not import helpers from `FromOptree.pm`. Shared
code is shared assumptions.

## Phasing

**Phase 1 -- straight-line.** `Constant`, the binops, `Concat`, `Coerce`,
`PadAccess`, `Print`, `Return`, `Call` (builtins). Walk the control chain, emit
statements. Gate: a hand-written corpus of straight-line programs round-trips
with identical output.

**Phase 2 -- memory.** `MemStart`, `Subscript` reads with memory inputs,
`Assign`, `EntryDef`/`EntryWrite`, `Delete`, `ArrayLiteral`/`HashLiteral`.
Gate: the `keys`/`values`/`each` defect and the `@$r` mutation cases are
DETECTED by the oracle without being told where to look. That is the
acceptance test for the whole idea -- if it cannot rediscover a known open
defect, it is not earning its keep.

**Phase 3 -- control.** `If`/`Proj`/`Region`, `Phi`, `TernaryExpr`, `And`/`Or`,
`Loop`, `Unwind`. Gate: the nested one-armed element store (this session's open
blocker) is detected.

**Phase 4 -- the corpus.** Run over all of base+comp. Every CLEAN file must
round-trip to identical output, or produce a named refusal from the emitter.
An emitter GAP is fine; a silent difference is not.

**Phase 5 -- wire it into the suite** as a corpus gate, so a future producer
change that breaks a round-trip fails a test rather than waiting to be noticed.

## What this is NOT

  - Not a compiler backend. chalk owns lowering; this is a producer test
    harness and it must never become a second consumer with opinions.
  - Not a pretty-printer. Output is read by `perl`, not by people.
  - Not a replacement for the corpus survey. The survey says WHICH files
    translate; the oracle says whether what translated is TRUE.

## Cost and the honest caveat

A week or so for Phases 1-3 covering the corpus vocabulary, and it grows with
the IR -- every new node kind needs an emission rule or an explicit refusal.
That is a real ongoing tax.

The case for paying it: the last three defects found were all "the reader does
not observe the store", the class where the graph looks complete and computes
the wrong answer. Inspection is worst at exactly that, and one of the three is
still open.

## Open questions for review

1. **Scope.** Phases 1-3 to prove the concept, or straight to 4?
2. **Where does it live** -- `lib/SoN/Deparse.pm` in this repo, or a separate
   tool? In-repo means it tracks IR changes; separate keeps the producer
   dependency-free.
3. **Is a REFUSING emitter acceptable** as a permanent state for nodes with no
   honest Perl spelling, or does every node need a spelling eventually?
4. **Does this change the priority** of the remaining comp blockers? Building
   the oracle first would likely find defects in the 29 files currently CLEAN,
   which may matter more than the 5 PARTIAL ones.
