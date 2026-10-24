---
name: feature-references-and-real-aggregates
description: 430/430 goal, first whole feature — references (\@a \%h \$x, $$r, ref()), hashes with tags/insert/growth, reads by stored tag, exists, copy-deref, grep truth; ROUNDTRIP 95 -> 109; 114 chalk lli tests had been skipping on a hardcoded lli path
metadata:
  type: project
---

**The ask (perigrin, 2026-10-24):** "Then we start implementing whole
features." Iterating cause by cause had reached causes that are really
missing features.

**What references needed:**
- `\@a` and `\%h` are their referent's own heap pointer, used as a ref.
  `\$x` points at the `%Slot` of a variable that a reference makes into a
  location.
- `$$r` reads and stores the Slot.
- `ref()` answers statically by repr, or by the Slot's tag. A ScalarRef
  tag was added.
- A bound argument's repr wins where a container's repr is consulted
  (`_repr_of`).

**What hashes needed** (a store to a missing key had been silently dropped):
- `%HashEntry` gained a tag, after first moving its fields to a named
  list. The code's own note prescribed that order.
- A store to a key that isn't there inserts it, growing the entries by
  malloc and memcpy.
- `exists` is a key scan.

**Reads by stored tag, arrays and hashes alike:** an element read is one
Slot phi, converted by its stamp. Decoded by the stamp, an Int read as Num
was garbage, a missing key read as Str dereferenced null, and an
Undef-stamped read was a Slot where an i1 belonged.

**Exposed on the way, each fixed with a test that failed first:**
- `grep { $_ }` appended every element twice. The wire's `collector`
  field was being dropped.
- `my %p = %$h` aliased instead of copying (the deref's `copy` flag).
- `defined`, and `//`, over a dynamic-index read whose stamp was narrowed.
  This fixed backlog 9c217485.
- Two dominance holes: a pure value cached inside an if arm, and a
  loop-invariant literal first lowered in a loop body.
- An argument the callee left Unknown is now the caller's value as it is.
- Dropping an arm's cache broke the merge: the merge's phis lower each
  arm's value in that arm's tail, after the arm ends. The dropped values
  are kept aside and put back only there.
- `_graph_component` walked every consumer of `@_`. In an older wire one
  `@_` is shared by every graph, so another sub's `$_[1]` raised this
  sub's arity. Only the `my (...) = @_` Assign is followed now. Caught by
  the 114 un-skipped tests (inlined-arg-carries-its-repr.t).

**Coverage hole found:** 114 chalk test files hardcode
`/usr/lib/llvm-15/bin/lli` and had been skipping in every check this
session. Linked here. Base and head lists must be regenerated with it.

**Round-tripped:** ROUNDTRIP 95 -> 109, 0 wrong.
