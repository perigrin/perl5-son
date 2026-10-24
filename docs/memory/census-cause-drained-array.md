---
name: census-cause-drained-array
description: 430/430 goal, cause "a drained array is also read/mutated elsewhere" (7) — a read that carries its memory version is frozen, so it may see the array where it stands; ROUNDTRIP 164 -> 166 of 431
metadata:
  type: project
---

**Cause:** "a drained array is also read/mutated elsewhere" held 7
cases at a934d567. A loop that shifts/pushes an array in place was
refused if anything else used the array, for fear the use would see
it half-mutated.

**Built (chalk 05bb1a05):** `_prelower_loop_drain_operands` skips a
use that reads at its own memory version (`_reads_at_its_memory_version`):
a Subscript/Exists with inputs[2], a Count with inputs[1], or a
join/sort/reverse/keys/values with `memory_input`. Those reads are
pinned by `_freeze_memory_reads`, so they see the array as it stood.
Any other use stays refused. Test:
t/bootstrap/ir/llvm-a-mutated-array-is-read-where-it-stands.t (failed
3/3 first).

**Result:** 2 of the 7 round-tripped (164 -> 166). Census agreed 3/3
runs. The rest hit next: 2 still refused by name (a literal holding
the array), 2 hit "element read across a branch-guarded store needs
a memory-Phi", 1 other.

**Why:** the guard predates read freezing; once reads carry their
memory version the guard was protecting against nothing for them.
**How to apply:** before relaxing a "used elsewhere" guard, check
whether the use is versioned; unversioned uses still need it.
