---
name: count-a-call-as-a-store-only-where-it-reaches
description: counting every user call as a store to any container reached through a reference turned correct renders into refusals; reverted, the narrow miscompile went to followups
metadata:
  type: feedback
---

A read `$info->{s}` through `$self->vars->{$k}`, used after
`$self->init($k)` deletes it, was spelled after the call (wrong). The
in-loop stale pass counts a call as a store only when it is passed an
element of the container. Counting every user call for a container
reached through a reference fixed it, but refused two working renders
(a deref read whose uses sit outside the body).

Also reverted: copying `my %p = %$h` instead of binding the deref
(right, and broke 7 files through readers that relied on the binding).
Both are logged in followups with repros.

**Why:** a soundness widening in a shared pass moves every shape the
pass sees, not only the target.

**How to apply:** before widening, run the full suite and count what
newly refuses or changes. When it spreads past the target, back it out,
log the miscompile with a repro, and plan it as its own change.
