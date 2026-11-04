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

## Done: chalk a9628f32 (slice 3: subs, if/else, my in memory)
- A direct sub is `%Slot (%Slot args)`. A sub's argument and its result
  are %Slot, because T1 types them per call site (add(2,3) is Int though
  add(0.5,1) is 1.5).
- %Slot arithmetic is perl's: Ints stay Ints until they overflow. Numify
  parses integers whole (strtoll). Both keep 2^53+ digits.
- if/else: each arm's memo is kept for its phi inputs, so a call in an arm
  isn't made twice.
- my in memory: an alloca %Slot. Each read is made before any store that
  replaces its version, before an if, and at loop headers. Lesson: a
  node's consumers don't list every value use, and B::SoN makes the store
  target and the read at one version a single node. So read them all.
- ++/-- are perl's, including the magic string increment.
- Refused: optional signature parameters (pvm 030 went DIFFERS until
  refused), a call of another arity.
- 54 corpus cases go through T2 (was 38). Census 391, 0 DIFFERS.

## Slice 4: arrays (perigrin chose, 2026-11-04)
- The slice-3 ratchet passed (6/6).
- Why: the corpus's first blockers include push 46, ArrayLiteral 23,
  Count 26, Subscript 9. Methods (53) need arrays later anyway (@_ and
  objects).
- Scope:
  - a `my @a` is an %Array of %Slot, by pointer, in T2 (alloca'd header
    or heap);
  - literals, push/shift/pop, $a[i] reads and stores (negative indexes and
    growth), scalar(@a), "@a" (join with " "), foreach over an array.
- Out: arrays passed to or returned from subs, nested arrays and refs,
  splice, sort, slices, wantarray.
- Tests are red first.

### Slice 4 as built: chalk cb301529
- An array is `%Array* = { len, cap, %Slot* }` on the heap. An array whose
  literal holds only constants is made in the entry block. An array first
  made in an arm or a loop body is refused, because it would be made again
  on each pass.
- B::SoN folds a constant literal into its uses: `"@a"` reaches chalk as
  `join($", "x", 1.5, 2)`. So join takes scalars into a fresh array.
- Lesson: a read that needs a phi not yet made (`$a[$i]` in a foreach)
  can't be hoisted by reads_before; it is made where it is. And a loop's
  exit Region has its own one-input memory phis. A read after the loop is
  at that phi, so it is a passed version too. (Without it, `my $s = $a[0];
  $a[0] = 6` after a loop printed 6 6.)
- `$a[-N] = v` past the start dies with exit 255. Perl's text is printed
  through the subscript. Follow-up: B::SoN gives a store no file and line
  (only Divide and Modulo have a site), so the " at FILE line N." tail is
  missing.
- Result: 67 corpus cases go through T2 (was 54). The census stays at 391
  with 0 DIFFERS: the cases T2 took newly were already round-tripping
  through the fallback. No pin.
- Next first blockers in T2: statement ArrayLiteral 33, an array that is
  not a `my` array 30, a statement Call 44, EntryWrite 26, HashLiteral 23,
  PackageMark 21, a phi stamped Array 11.
- Found: s2 (`for my $x ("x".."z")` prints only x). B::SoN builds a
  string range as a numeric count. It's a producer bug, pre-existing at
  a9628f32.
- Fixed (chalk 3bc53c06): a `my @a` in a loop body or an arm is fresh on
  each pass. B::SoN already pins the declaration (it has a control_in). My
  first diagnosis ("identical graphs, a producer bug") was wrong: my dump
  didn't print control edges, so print control_in before blaming the
  graph. Context's _prelower_loop_drain_operands hoisted a pushed array
  out of the loop even when it was pinned. T2 now makes a pinned literal
  where it stands.
- Lesson: never `git stash` to see the base. With a clean tree it saves
  nothing, and `pop` then applies an old stash. Use a worktree
  ($S/wt-s3 is at a9628f32).
