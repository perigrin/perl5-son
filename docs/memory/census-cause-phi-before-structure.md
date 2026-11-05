# Cause: "Phi node encountered in lower_value before its enclosing if/loop structure" (2026-11-05)

- Held: pvm 210 and 224.
- 210 is a runtime string eval (`eval 'package Other; sub g {...} 1'`). It
  belongs to the eval family that was backed out, so it was not worked.
- 224 shrank to: an early return in an `if`, then a loop storing to a hash
  (`unless (@a) { return } $h{$_} = 1 for @a`).
  - `_prelower_branch_store_operands` makes, before an if, the operands of
    every store in its arms. It walks into nested loops, so it made the
    loop's counter-element key before the loop existed.
  - Fix (chalk a5f14544): skip an operand that `_reaches_an_unlowered_phi`;
    the loop body makes it.
- PRE-EXISTING MISCOMPILE found while shrinking (chalk 9570c5bf):
  `local $x = 0; $x += $_ for 1, 2; return $x` returned 0. The return's
  read is at the loop's exit memory Phi, which no store freezes, so it was
  made at the Return, after the restore (EntryWrite / ElemRestore).
  - Fix: before such a restore whose memory input is a memory Phi,
    `_freeze_memory_reads` on that Phi.
  - It hit `local` on scalars, hash elements and hashref elements, after a
    loop or an if.
- Lesson: shrink a refused case by hand. Its pieces can be silently wrong
  on their own, as m3/m13 were here.
- Result: 224 round-trips. Census 399 -> 400.
