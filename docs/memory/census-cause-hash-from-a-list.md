---
name: census-cause-hash-from-a-list
description: 430/430 goal, "a hash literal that flattens a list among its pairs is not lowered" (070 084 176 228) -- built pair by pair from the flattened list; older silent wrong found: repeated keys kept every pair; 248 -> 250
metadata:
  type: project
---

**Cause:** "a hash literal that flattens a list among its pairs is not
lowered" (070 084 176 228): `my %o = @_`, `map { $_ => ... }`, `{ %$c, n => 1 }`.

**Built (chalk c848ef18):**
- `_lower_hash_from_pairs`: an empty %Hash (zeroinitializer header; insert
  grows from a floor of 4), then each pair UPSERTED -- statically for fixed
  pairs, or over `_emit_flattened_array_of(inputs)` two slots at a time at
  run time (key read as Str by tag, a missing last value undef).
- `_emit_flattened_array_of`: a Hash input is its pairs (entry walk: key as
  a Str slot, value from the entry's def/tag/pay).
- `_emit_hash_upsert`: the element store's inline key scan + insert, moved
  out unchanged and shared.
- **Older silent wrong:** the entry-per-pair literal kept repeated keys --
  `(a => 1, a => 3)` read 1 with 2 keys (perl: 3, 1 key); `("a")` crashed
  on 0.5 pairs. The fast path now needs distinct constant keys and whole
  pairs; anything else upserts.

**Result:** 084 228 round-trip; 248 -> 250. 070 moved to an untyped
Region Phi (`defined $v ? $v : []`), 176 to the Scalar-container store
(autoviv) cause.

**Lesson:** a literal's "one entry per pair" is only true when the keys are
known and distinct -- a constructor that assumes its inputs are unique
needs that checked, not assumed.
