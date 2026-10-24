---
name: census-cause-local-alias
description: 430/430 goal, causes "cannot lower op=LocalAlias" (7) and "ArrayRef elem has repr=Undef" (5) — $_ aliased through a pointer global, saved/restored by the loop; undef elements; ROUNDTRIP 130 -> 136
metadata:
  type: project
---

**Causes:** "cannot lower op=LocalAlias" (7 cases) and "ArrayRef elem[N]
has repr=Undef" (5 cases), at 9f7e363d.

**LocalAlias** is B::SoN's `local *_ = \$a[$i]`: a foreach whose callees
read or write `$_` by name. The design is real aliasing through one
level of indirection, not copy-in/copy-out:
- A package scalar that some LocalAlias moves is read and stored
  through a `%Slot*` global (`@pkg_main___at`). The set is found by a
  pre-scan through call targets (`_scan_local_aliases`, kept in the
  `%ALIASED` package var, set in `lower_with_elaboration`).
- The alias points it at the element's slot. A pass over values
  (`for 1 .. 2`) gets a fresh slot instead.
- The loop saves the pointer into its preheader block's instructions
  and restores it in its exit block, which a `last` reaches too.
- The element ref carries the growth guard from the foreach-alias
  cause.

Copy-in/copy-out was rejected here because a direct element access
during the pass would see stale data.

**Undef elements:** an undef in a list literal is a slot with its
defined bit clear.

**Round-tripped:** 130 -> 136. 197, 193, 196, 329, 332 and 402 work
now.

**What the rest hit:**
- `uc` (034).
- `sort` with no folded comparator (087).
- `blessed` (180).
- A `shift` arity mismatch (174).
- MOP: no class_name (248).
- A Region.Phi over ArrayRef and Unknown (073).
