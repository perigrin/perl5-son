---
name: census-cause-delete
description: 430/430 goal, "node op=Delete repr=Scalar" (4) -- hash delete, values; found a producer miscompile (an element read took ANOTHER slot's store type); 210 -> 214 of 431
metadata:
  type: project
---

**Cause:** "node op=Delete repr=Scalar reached LLVM backend" (070 227 302
303).

**Built (chalk 6a4ede45, perl5-son "An element read takes only its own
store's type"):**
- @chalk_hash_delete(%Hash*, key, len) -> %Slot: a linear scan, the
  value as a Slot (zeroinitializer is undef), and the entries after it
  shifted down so keys keep their order. HashEntry field indices are
  interpolated from _he_idx/_slot_idx, never written as literals.
- values %h: the keys walk with each entry's val_def/tag/pay copied into
  the slot.
- Delete added to the ops after which process_control_node freezes
  memory reads. Without that, `@v = sort values %h; $h{d} = 4` put 4 in
  @v: the read was lowered at its use.

**Producer miscompile found:** B::SoN's _floor_subscripts gave an untyped
element read the type of the Assign its memory version is -- even a store
to a DIFFERENT slot. `$h{d} = 4` then `map { "$_=$h{$_}" } sort keys %h`
typed the sorted keys and the values Int, and chalk printed 0=0,0=0,0=0.
This was already wrong in committed chalk; nothing in the census caught
it. Now only a store to the same container and index (same node, equal
constant, or a same-named variable) types the read.

**Lesson:** when a new probe gives a wrong answer, stash and re-run at HEAD
before blaming the new code. Twice this session it was older.

**Lesson (cleanup):** `rm -f t/*.tmp.*.pl` deleted a TRACKED file in
perl5-son (t/deparse-conditional-eval-scope.t.tmp.2270129.pl). Check
`git status` after cleanup; restore with git checkout.

**Result:** 210 -> 214 (302 and others). Next: 303 (hash slice as a value),
227's sort of values, 070 (a hash literal flattening @_).
