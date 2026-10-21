---
name: the-foreach-alias-is-a-reference
description: a foreach iterator bound to a pass-top element copy disagreed with perl's alias once a call changed or moved the element; a reference taken per pass is the alias
metadata:
  type: feedback
---

The array foreach bound `$x` to `Subscript(arr, i)` read at the top of the
pass. A callee that shifted the list (`bb;dd;` for `aa;cc;`) or changed
the element in place, or that wrote `$_[0]`, was invisible to that copy,
so such bodies refused ("unproven list ... (a call)") -- or, over a deref
or anonymous list the refusal did not cover, miscompiled (baseline).

**Why:** perl's iterator is an alias that stays on its element; an index
read is neither stable under a shift nor live under an in-place change.

**How to apply:** where the body may reach the list (and does not write
the iterator, take `\$x`, or iterate `$_`), take `exists ? \$a[$i] :
undef` pinned at the pass top and read the iterator as `exists ? $$ref :
$a[$i]` (a hole is aliased lazily, never vivified). Pin a read only at
the body's statement level -- in a branch the arms may share one control
node -- and never let a scout's walk touch the real reference (its own
factory leaked a node through it). A call argument stays inline: bound to
a temp it is a copy, and `$_[0] = ...` was lost.
