---
name: every-scope-exit-restores-its-locals
description: a `local` was restored only at leaveloop, unstack and leavesub; an if arm's leave and a folded block's leave restored nothing
metadata:
  type: feedback
---

`our $g = 1; sub f { if ($_[0]) { local $g = 2; g() } g() }` emitted
`g=2 g=2` for perl's `g=2 g=1` (baseline too), and `if (1) { local
... }` -- folded to a plain enter/leave block -- likewise. The restore
ran at leaveloop (bare blocks), unstack (loop bodies) and leavesub, the
shapes someone had measured; an arm's `leave` and the main walk's
plain `leave` had none.

**Why:** the save/restore was wired per scope SHAPE, so every unlisted
shape was a silent leak, and the tests used bare blocks and subs.

**How to apply:** record the local_saves count at each `enter` and
restore to it at the matching `leave`, in every walker. A local on an
ELEMENT rides the same list: the store is an Assign marked `local`
(the deparser opens a block and spells `local`), and the block's exit
is an ElemRestore (saved value, existed, memory) the deparser renders
as the closing brace. Refuse where a path skips that node: an
eval/try, a loop control out of the block.
