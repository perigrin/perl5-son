---
name: an-argument-is-an-alias-for-an-array-too
description: a callee's `$_[0] = 5` writes an array element or array it was passed; the flatten shortcut must stop folding that array's later reads; and never `git checkout` a file in an uncommitted session tree
metadata:
  type: feedback
---

`sub g { $_[0] = 5 } my @n = (1,2); g($n[0]); "@n"` emitted `1 2` for
perl's `5 2`, and so did `g(@n)` and `g($_) for @n`. They were on the
base too. Scalars and hash elements were right: `_address_taken` demotes a
scalar argument, and a helem goes through memory. The call itself was
emitted as the alias (`g($n[0])`). Only the later list read was wrong,
because the padav flatten shortcut pushed the literal the array was built
from.

The fix marks `$ctx->{mutated_aggregate}` when a padav, or the padav under
an aelem, is consumed by an `entersub`. It also marks `$MUTATED_LITERALS`
for a `$_` or package foreach list when `_iterator_may_be_written` holds.
Use `_operand_consumer(...) eq 'entersub'`, not `_is_call_argument`, which
also answers yes for `sort`. That moved four corpus IR blocks for nothing.

Separately, a `git checkout FILE` to undo one tool run reverted the
session's earlier, uncommitted refills of that file to HEAD. The next
`--check` showed drift that looked like a regression. The same applies to
`git stash`.

**Why:** perl passes every argument by alias. A flatten that skips memory
cannot see a write it has no node for.

**How to apply:** when a read emits no node, ask what could have written
the container since it was built. To undo a generated file, regenerate it
or restore it from the latest checkpoint patch, never from HEAD.
