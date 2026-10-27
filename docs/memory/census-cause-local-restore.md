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
