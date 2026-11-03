# Plan: the first T2 slice (perigrin: "Start the T2 slice now", 2026-11-03)

Trigger: Num ⊔ Str. T1 types the merge Str, but its repr must box the Num.
Doing that inside Context.pm meant every Str consumer asking the repr seam
(stashed attempt: regressed 003 and 373). In T2 the repr is chosen once,
when the LLVM-shaped graph is built, and every node there carries its LLVM
type, so no consumer has to guess.

## Shape (agreed earlier)
- T2 is a new graph per target, typed in target types; T1 is never mutated.
- It can change shape: unbox/box are nodes, runtime calls are nodes.
- No shared intermediate layer.
- Emitting is printing T2.

## Slice 1: straight-line scalars, with the Str/Num repr choice
- Scope: a program with no subs, no loops, no aggregates. Constants
  (Int/Num/Str), arithmetic, comparisons, `?:` and if/else merges, Concat,
  `print`.
- Strangler: the T2 path takes a program only if every node is in scope.
  Otherwise Context.pm lowers it as today. A refusal inside T2 falls back
  rather than failing.
- Repr solver: each T1 value gets an LLVM type (i64 | double | %Str | i1 |
  %Slot). A Str merge that a Num reaches gets %Slot. Arms box into it;
  consumers unbox (Slot->Num by tag, Slot->Str by tag).
- Builder output: blocks of T2 nodes (Add.i64, FAdd.double, Box, Unbox,
  Call @chalk_..., Phi.%Slot, Br, CondBr, Ret).
- Printer: one line per node; no decisions.
- Tests:
  - `$c ? 0.1+0.2 : "x"; $v == 0.3` gives ne.
  - The interpolation prints 0.3.
  - Ints and strings round-trip through T2.
  - A program out of scope falls back with identical output.
- Done when the slice's tests pass through T2, the census holds (fallback
  covers the rest), and mg2 round-trips.
