---
name: a-lookup-returns-a-value-not-a-name
description: sim->lookup returns the SSA binding, so a store target resolved that way is a value and the write is silently dropped
metadata:
  type: project
---

In `SoN::FromOptree`, `$sim->lookup($key)` returns whatever the scope key
is currently BOUND to -- a value node, not a name. `_entry_store` guards
on `EntryDef`, so handing it a lookup result silently emits NO store.
Silent, because the guard is a `return unless`.

Measured on `our $g = "aaa"; $g =~ s/a/b/; $g =~ s/b/c/`: the key was
bound to the Constant "aaa", so no write-back was emitted, both
RegexSubst nodes were orphaned, and the program printed `aaa` where perl
says `caa`.

The fix is the name/value SPLIT: return the bound value as the operand
(it is the subject the node reads) and rebuild a fresh `EntryDef` beside
it as the store target. `_subst_target`'s `$_` branch had done this for a
while; the package branch had not.

**Check every branch of a resolver when one gets this fix.** The comment
on the `$_` branch explains the hazard in full and the branch fifteen
lines above it still had the bug.

Related: [[one-operator-five-declaration-sites]],
[[allow-lists-fail-asymmetrically]].
