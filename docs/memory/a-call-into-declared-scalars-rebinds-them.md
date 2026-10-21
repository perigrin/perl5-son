---
name: a-call-into-declared-scalars-rebinds-them
description: a list assign from a call into scalars declared earlier left them bound to their old values; a `my` slot is its own PadAccess, a declared one is not
metadata:
  type: feedback
---

`my ($a, $b); ($a, $b) = g(); $b += 1` emitted ` 1` for perl's `5 3`
(baseline too). A call has no positions, so the aassign left the
bindings alone -- right for `my ($a, $b) = g()`, whose LVINTRO padsv
seeds each slot with its own PadAccess, wrong for scalars declared
earlier, which kept the `my`'s undef. `($lo) = g()` was worse: the
single-target exception bound $lo to the whole call (`52`).

**Why:** the rule "leave flattening RHS bindings alone" was written and
tested only on the declaring form, where leaving alone happens to mean
"bound to the slot".

**How to apply:** after a non-positional list assign, rebind each
declared scalar pad target to its PadAccess and pin the Assign on the
control chain. Pinned in an arm it is a statement there, so the
deparser's `my (...)` hoisting must see list declarations too. Found
by chasing a refusal (LLVM::Context) down to its IR, not the emission:
read the Phi's inputs before blaming the renderer. The same chase
found `my @c = split ...` bound as the call (`\@c` was `\(split...)`)
and `@pkg = split` dropped -- split assigns its target itself, with no
aassign, so aassign's container rules never ran.
