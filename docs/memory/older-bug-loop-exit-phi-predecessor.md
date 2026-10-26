---
name: older-bug-loop-exit-phi-predecessor
description: Older invalid IR (wrong at the session's baseline): a loop with a mid-body `last` whose header opened blocks (a stringify) named the header's FIRST block as the exit merge's predecessor; found probing 115; fixed in chalk
metadata:
  type: project
---

**Symptom:** `for my $j (1 .. 5) { $s .= "<$j>"; last if $j == 3 }` --
lli: "PHI node entries do not match predecessors". Wrong at the session's
baseline, the committed HEAD before the fix, and in no corpus case (the
census never saw it; a probe for 115's nested-`last` shape did).

**Why:** `_lower_loop` builds the multi-exit merge (header-false OR a
mid-body `last`) over `[$header_label, @break_blocks]`. A header that
lowers a Concat of a number opens the digit loop's blocks, so the header's
exit branch is in its LAST block, not `$header_label`.

**Fix:** the block current when the header branch is emitted
(`$header_exit_from`) is the predecessor named.

**Lesson:** a label captured BEFORE lowering is not the block that ends
it -- every site that names a predecessor must read `_current_block_label`
after the lowering that precedes its branch (the same rule `_lower_and`'s
`$rhs_end_label` follows).

**Still refused (115's own cause):** `last LABEL` / `next LABEL` to an
outer loop: "Phi node encountered in lower_value before its enclosing
if/loop structure was processed".
