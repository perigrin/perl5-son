---
name: a-parameter-name-at-top-level-is-the-parameter
description: a demoted signature parameter stored into again was spelled `my $c = ...` (masks warning); marking the name declared everywhere took the `my` off an inner shadowing `my $x` in a loop
metadata:
  type: feedback
---

`sub f ($c) { $c = g($c); ... }` with `$c` passed to a call (demoted):
the parameter's entry store emits nothing (the signature declares it),
so the next store was taken for the slot's first and got `my`. The IR
has no slot identity for scalars (no targ, no LVINTRO on Assign).
Marking the name declared broke `for (...) { my $x = $_; push @l, \$x }`
over a parameter `$x`, where every reference then aliased one variable.

Fix: the parameter store marks its name `'param'`. A later store to that
name drops `my` only on the sub's top-level chain (`_at_top_level`:
walk control back to Start without passing a Proj; a Region steps to
its head's control). Under an arm or a loop body it keeps `my`.

**How to apply:** when the deparser decides `my` by name, ask where the
store is. A name is not a slot. Check what a pre-existing test covers
before widening a "declared" set.
