---
name: census-cause-conditions-on-inlined-arguments
description: 430/430 goal, "_ensure_i1 cannot convert repr=Unknown" (3: 071 152 199) -- !, ?: and && on an inlined `my ($k) = @_` read the caller's repr; found two older miscompiles on the way (a reference tested false; a guarded deref was hoisted); 225 -> 226
metadata:
  type: project
---

**Cause:** "_ensure_i1 cannot convert repr=Unknown to i1" (071 152 199).
A `my ($k) = @_` is stamped Unknown; inlined, it holds the caller's value,
which `_repr_of` knows. Not, the ternary and And/Or read the bare stamp.

**Built (chalk):** `_lower_not`, `_lower_ternary(_by_slot)`, `_lower_and/_or`
take `_repr_of(...) // stamp`. An Unknown And/Or whose two sides are scalars
is typed by them (agreeing sides keep their type, otherwise Scalar).

**Two older miscompiles this exposed (both wrong at HEAD, now fixed):**
- A Slot holding a reference read as Boolean tested FALSE:
  `_emit_read_slot_as` dispatched only Int/Num/Str/Boolean tags and sent
  every other tag to the undef arm. A reference tag is now true (Opaque
  still falls to the undef arm). `my @a = ({}, 0); $a[0] ? ...` gave "f".
- `_freeze_memory_reads` lowered `$x->{v}` at entry, ahead of the
  `if ($on && (my $x = ...))` that guards it, so the not-a-reference exit
  fired where perl never read it. A read through a Scalar container is now
  left at its use when no later version of that memory exists.
  (With a later store it is still frozen early -- the pre-existing
  behaviour; refusing it would need a guard-aware freeze.)

**A type a lowering learns belongs to that lowering, not the node.** The
first cut wrote the And/Or merge's type with `set_stamp`. A callee graph is
shared by every call that inlines it, so `w(1, 2)` stamped the And Int and
`w("x", "y")` then read "y" as an Int: `2|0|2|0` for perl's `2|y|2.5|`. It
is now kept in the lowering's cache (`repr:<id>`, read first by `_repr_of`)
and handed to the call site as `_inlined_value_repr` before the callee's
cache is dropped. Any `set_stamp` inside a callee graph is suspect.

**Also here -- `C ? @a : @b` in list context (199's first refusal):** both
arms Array is branched, each arm lowered in its own block, and the %Array*
pointers merged: the list IS the taken arm's array (aliased, as perl's is).
`join` over `my @r = ($c ? @a : @b)` took the literal list's static
elements and printed the ternary as one (its count); an ArrayLiteral with
an aggregate among its inputs has no static elements now. 199 next hits
"an argument stamped Array flattens into @_, which inlining does not build".

**Lesson:** turning a refusal into a lowering surfaces whatever was wrong
downstream. Probe the new shape with values that take EVERY path (152 was
only wrong for f("a",0) and f("b",1)).

**Result:** 152 round-trips; 225 -> 226. Next: 071 hits a Region Phi
Str->Unknown arm; 199 a ternary of two Arrays (list-context ?:).
