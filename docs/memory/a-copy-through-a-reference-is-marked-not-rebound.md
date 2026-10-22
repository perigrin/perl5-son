---
name: a-copy-through-a-reference-is-marked-not-rebound
description: `my %p = %$h` was bound to the dereference and read live; mark the PostfixDeref `copy` and let the deparser snapshot it instead of rebinding (the rebinding broke 7 files)
metadata:
  type: feedback
---

The producer binds `my %p = %$h` to the PostfixDeref itself, and
readers rely on that binding. So `$h->{a} = 2; $p{a}` read 2 for perl's
1. Rebinding `%p` to a fresh HashLiteral broke 7 test files.

What worked:
- Keep the binding, but make a distinct PostfixDeref with `copy => 1`.
  A foreach's dereference stays unmarked and live. The JSON only gains
  `copy: 1` (plus the old deref left unused).
- In the deparser's list-deref snapshot pass, count element reads, an
  `exists` and literals built from the copy as readers. The pass then
  binds `my %staleN = $h->%*` at the copy's version.
- For a copy, the walk that looks for a later store goes through arms
  and loop bodies (`%arm_next`), and the "under a loop" skip is lifted
  unless the version is the loop's own.
- Run that pass for copies BEFORE the element-in-loop pass, so element
  bindings spell `$staleN{k}`, not the live source.
- The undeclared-name scan read `$stale3{a}` as `$stale3`. An element
  names its aggregate.

This took Schedule::Elaborate (`my %pre = %$val_map`) to COMPILES.

**How to apply:** when a binding many readers depend on is semantically
wrong, add the missing fact as a field on the node and correct it at
emission. Don't change the binding.
