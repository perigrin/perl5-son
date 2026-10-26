---
name: census-cause-slices-as-lists
description: 430/430 goal, "Length operand has repr=List" (3: 075 164 223) -- grep/map over an array slice walk the slice made once (writes through $_ refused: perl aliases); a hash slice in a list is each key's value; 075 is a different shape (a list with a List in it)
metadata:
  type: project
---

**Cause:** "Length operand has repr=List; only Array and Str are lowered"
(075 164 223).

**What it was:** B::SoN walks `grep { } @a[...]` as a loop over
Count(Slice) and Subscript(Slice, $i). A List has no length and no
elements here. An array Slice used as a container now lowers to a fresh
%Array* (`_emit_flattened_array_of`, already the slice-in-a-list path), and
Length/Subscript read it as an Array.

**Kept honest:** perl's `$_` in that grep is the ARRAY'S OWN element --
`grep { $_ = 9 } @a[0, 1]` changes @a. The walk here is of a copy, so an
element written (`=`, `++`, `s///` all arrive as Assign), referenced or
passed to a sub is refused by name. Measured each with a probe.

**Hash slices (223 next hit "join over an operand with repr=List"):**
`_lower_hash_read`'s key scan is now `_emit_hash_slot_of($hash, $key)`,
returning the %Slot (undef on a miss); `_emit_hash_slice_into` pushes one
per key in order. A key list that is itself a list (`@h{@k}`) is refused.

**Result:** 164 and 223 round-trip. 075 is another shape: `return ()`
beside `return @c` -- "a list with a List in it is not lowered".
