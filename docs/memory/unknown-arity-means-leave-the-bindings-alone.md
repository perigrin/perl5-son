---
name: unknown-arity-means-leave-the-bindings-alone
description: A list assign from a single Call cannot be distributed positionally; perl does it at runtime
metadata:
  type: project
---

`my ($a,$b) = SOMETHING` has two shapes the graph cannot tell apart:

    my ($a,$b) = times              a=0, b is a REAL value
    my ($a,$b) = one_value_sub()    a=7, b is undef

The producer's positional rebind guessed the second and destroyed the
first: `$a` took the Call, `$b` took undef, the slot bindings a later read
resolves through were gone, the Assign was orphaned, and DCE removed the
whole statement.

**The rule recognised flattening by STAMP**, and the list builtins are
deliberately unstamped — TypeLibrary has no row for `times`, `stat`,
`localtime`, `caller` or `split`, each being context-sensitive or
returning a structure. `sort` escaped only because it arrives stamped
`List` from elsewhere. That asymmetry was the bug.

**The fix is to do nothing.** When the single RHS is a Call, leave the
bindings alone: each slot stays bound to its own `PadAccess`, the Assign
names them as targets, and PERL performs the distribution at runtime.
That is correct for both arities without knowing either — and it is what
`sort` was already doing.

Related: [[assign-targets-are-positional]], [[op-names-are-not-perl-spellings]].
