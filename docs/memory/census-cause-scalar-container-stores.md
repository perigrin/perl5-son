---
name: census-cause-scalar-container-stores
description: 430/430 goal, "Assign(Subscript-lvalue) container has repr=Scalar" (176 184 225 232 233) -- stores through a tagged reference, autovivify into an element or a location; found an older loop-read wrong and two hazards now refused by name; 256 -> 257
metadata:
  type: project
---

**Cause:** element stores whose container is read by its tag (176 184 225
232 233). Deferred once because a store cannot just mirror the read path
(exit on undef): `$a[0]{k} = 1` autovivifies.

**Built (chalk ca4e8fde):**
- `_lower_assign` takes a Scalar container as ArrayRef/HashRef by its lvalue
  kind, `autoviv => 1` to `_container_ptr`: tag right -> the pointer; undef
  where it can be WRITTEN BACK (`_autoviv_target`: a location PadAccess, an
  array/hash element -- not a bound argument copy) -> a new aggregate stored
  there (`_autoviv_store`: location store / extend+slot store / upsert),
  merged by a phi; anything else exits 255 (perl dies on a non-ref; an
  undef copy has nowhere to go -- the one stop).
- **Older silent wrong fixed:** reads at a loop's memory phi were never
  frozen; used in an arm after the pass's store they read the store
  (`my $s = $v{$k}; $v{$k} = "z"; if (..) { push @l, $s }` -> "z z").
  `_freeze_memory_reads` now runs on the loop's memory phis at the BODY
  START (header runs once more than the body; post-loop reads use the
  exit's memory). Reads through a tag (and a deref of one) wait there --
  hoisted, 124's `$i->@*` ran ahead of its `if (ref $i)` and exited.
- **Hazard refused:** a read through a reference left to its use is
  recorded (`_pending_tag_reads`); a store through a reference refuses
  while one is pending. A direct call storing through its argument has no
  memory input on the wire, so "a later version exists" could not see it
  (233 read "z" for "x"; 184's foreach alias of an element g changes).
- **`local` store refused** (Assign `local` field loaded): chalk does not
  restore it and the restore (ElemRestore) is not always on the wire --
  176's `local $self->{c}` stayed.

**Result:** 232 round-trips; 256 -> 257. 176 184 233 refused by name, 225
moved to `Coerce[HashRef->Str]` (a ref as a hash key).

**Lessons:**
- Widening a lowering exposes the ordering bugs a refusal was hiding: run
  each newly reachable corpus case, not just the new test.
- The producer does not chain direct calls into memory, so any chalk
  reasoning of the form "no later memory version" is blind to stores an
  inlined callee makes. The proper fix is producer-side (a call to a sub
  that stores through its arguments is a memory version).

**Follow-up (chalk d75ad368):**
- `_prelower_loop_store_operands` lowered a body store's container in the
  preheader as loop-invariant; `$r[$i]` / `$v{$k}` reached the loop phi
  first ("Phi node encountered ... before its enclosing structure"). Now
  the container's loop-invariant ROOT (walk Subscript/PostfixDeref down
  while it reaches an unlowered phi) is lowered there.
- **Older silent wrong:** only the loop's own statements were scanned, so a
  store in a nested loop or an arm left its aggregate to be made inside the
  body -- dropped with the body's cache and made AGAIN after the loop
  (`$m[$i][$j] = ...` -> "0 0;0 0"). Nested Loop bodies and If arms are walked.
- Not changed, recorded: a READ through an undef element (`$c{a}{n}`,
  `$c{$w}{n}++`) exits 255 where perl autovivifies even on fetch. Making
  reads autovivify is unsafe while reads through a tag can be frozen ahead
  of their guard -- they would create entries perl never makes.
