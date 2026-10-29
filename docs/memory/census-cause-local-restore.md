# Census cause: `local` on an element is put back

**Cause:** "a local store is not lowered -- what it replaced is not put back"
(added at pin 264 to stop a wrong answer in 176). It held 176, 177 and 178.

**Round-tripped:** 176 and 178 (264 -> 266). 177 now hits "element read across
a branch-guarded store needs a memory-Phi" (the 125 / 191 cause).

## What was done

- Under SSA a `local` is not a phi. The saved value is an ordinary read made
  before the local store. The restore is a store (or a delete, when the key did
  not exist) at each way out of the scope. The producer already made one
  `ElemRestore` at a block's end and at the sub's end.
- **Chalk:** lowers `ElemRestore` on a hash: an upsert of the saved value, or
  `@chalk_hash_delete`. A local `Assign` lowers the restore's saved-value and
  existed inputs *before* its store. It finds its restore by matching the
  container and key: the restore's memory input is the latest version, not the
  local store. A local `Assign` with no matching restore is still refused.
- **Producer:** a `return` puts back every `local` of every scope it leaves.
  Each walk (main, loop, branch) kept its own `local_saves`, so a return in an
  arm or a loop body saw none of the enclosing saves. `our @SAVES_STACK` holds
  the save list of every walk under way. A return restores (LIFO) from a copy of
  all of them, so the paths that do not return keep theirs.
  `_restore_locals_for_return`.

## Lessons

- A scout pass records no exit. A restore made there is an orphan node that
  still goes out on the wire (3 restores where 2 were wanted). Skip it when
  `$IN_SCOUT` is set.
- To restore on a return, look at every walk the return leaves, not just the
  current walk's ctx: each walk's state is local to it.

Tests: chalk `t/bootstrap/ir/llvm-local-on-a-hash-element-is-put-back.t`;
producer `t/wire-a-return-puts-back-what-local-replaced.t`.
Probes: lo9 and lo10 ROUNDTRIP; lr3, lo7, lo8 refused by the memory-Phi cause.

## Follow-up: the restore on a way out spells no `}` (found by SON_RATCHET)

The return's restore broke the deparsed Perl of chalk's own lib.
- **Symptom.** Context.pm's `_lower_call_direct` (a sub-level `local`, then an
  `unless (@args) { return ... }`) rendered "syntax error near } else". Lib
  COMPILES fell 179 -> 177 and gate3 SAME fell 482 -> 368.
- **Bisect.** The first bad commit was f3328f3.
- **Cause.** Deparse spells every ElemRestore as the `}` that closes the
  `local`'s block, so a second restore on the return path closed the block
  twice.
- **Fix.** An ElemRestore made on a way out of the sub (a return, or the sub's
  end; not the program's end) carries `at_return`. Deparse spells nothing for
  it and opens no block for it, because perl's own exit puts the element back.
  Chalk still lowers the restore.
- **Pre-existing, not fixed.** A block-level `local` whose block holds a
  returning `if` still puts the `}` of its leave restore inside the
  fall-through arm. `sub f { my $r = 0; { local $h{a} = 2; if ($_[0]) { return 7 }
  $r = $h{a} } $r + $h{a} }` prints 731 under perl and 441 deparsed, both
  before f3328f3 and after. Deparse only; it is in the report to perigrin.

Test: `t/deparse-a-local-left-by-a-return-closes-once.t`.
Lesson: a producer change that adds nodes must also be checked by rendering
chalk's lib (the SON_RATCHET lib census), not only by the corpus census.
