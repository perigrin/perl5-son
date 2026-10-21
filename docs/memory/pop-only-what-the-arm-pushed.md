---
name: pop-only-what-the-arm-pushed
description: `E // die` after a void list assign popped the assign's stack residue as the fallback value and merged a Phi of older residue
metadata:
  type: feedback
---

A void list assign (`($a) = ($ap)`) leaves its Assign on the sim stack.
The `//` handler walked the fallback arm and popped "the value" if the
stack was non-empty. A `die` arm pushes nothing, so it popped the
residue. Then `merge` compared the stack tops and made a Phi of two
residues (an Assign from three statements earlier). The deparser then
refused: "an Assign value with no target slots".

Fix: record the depth after popping the left side, and pop only above
it.

**Why:** a stack depth check (`> 0`) assumes the stack is clean between
statements. It isn't.

**How to apply:** any arm walk that takes "the arm's value" compares
against the depth at the snapshot, never against 0. When a merge makes
a Phi of nodes no arm computed, suspect residue. Print both sims' stack
tops before the merge.
