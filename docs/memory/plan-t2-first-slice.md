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

## Done: chalk adf5b627 (slice 1, behind CHALK_T2=1)
- lib/Chalk/Target/LLVM/T2.pm has three parts.
  - Node: immutable, each carrying its LLVM type.
  - Builder: chooses the repr once. A merge of different arm types is a
    %Slot. EnvRead and // are %Slot (they may be undef).
  - Printer: prints, with a small runtime of t2_* helpers.
- t/bootstrap/ir/t2-slice1-straight-line.t: 12 tests, red first.
  `$c ? 0.1+0.2 : "x"; == 0.3` gives ne.
- With T2 on, the corpus census is unchanged (391, 0 DIFFERS, 0 LLI_FAIL),
  and 34 cases go through T2.
- Known limit: a T1 node is built once, so a node first built inside a ?:
  arm and used after the join won't dominate its use. That gives invalid IR,
  not a wrong answer, and no corpus case has it. Fix in slice 2 (scope the
  memo to the block, or hoist).
- Next: perigrin decides when CHALK_T2 goes on by default. Then slice 2
  widens scope (if/else statements, `my` variables kept in memory, subs as
  defines).
- perigrin, 2026-11-03: no off switch. "T2 is the preferred architecture,
  why incur the technical debt?" CHALK_T2 is removed. A program in T2's
  slices always goes through T2. Context.pm is only the fallback for what
  no slice takes yet, and each slice shrinks it.

## Done: chalk 4e523b59 (slice 2: loops)
- Forward walk from Start. A Loop is a header of phis plus the condition,
  then the body back to the header, then the exit. A statement kind T2
  lacks makes the program fall back. Only the program's own Return ends
  the walk.
- The memo is scoped to each ?: arm and loop body (slice 1's limit is
  fixed). Modulo has perl's sign and dies on zero.
- 38 corpus cases go through T2 (was 34). Census 391, 0 DIFFERS.
- perigrin: a missing conversion is added, not fallen back from. The
  table is complete over i64/double/%Str/i1/%Slot.

## Slice 3: direct subs (planned 2026-11-03)
- Why: across the corpus, the first statement T2 can't take is a Call in
  141 programs. By kind, programs making each kind of statement call:
  direct 167, method 53, push 46, shift 16, indirect 10.
- Scope: a `sub f` called directly becomes a T2 function. Its arguments
  are its scalar @_ reads (shifts, $_[N]) or its signature; it returns a
  scalar.
  - Representation is chosen once per function: each parameter gets the
    join of what its callers pass. If those differ, it's a %Slot; the
    return gets the same treatment.
  - Recursion works because the function is defined before its body is
    built.
- Out: arrays, hashes and lists in or out, @_ written, wantarray.
- Tests (red first):
  - fact(5) recursive
  - a sub with a signature
  - a sub returning a number or a string
  - a sub called in a loop
  - a sub that prints
