# Census cause: each (389 -> 390)

**Cause:** "cannot lower op=Call builtin each". It held 021:
`my ($k, $v) = each %h`.

## What changed (chalk 67cf9f68)
- `_lower_builtin_each` gives each named hash variable an i64 iterator
  cell, made at entry the way a pos() cell is.
  - List context: an %Array of (key, value).
  - Scalar context: the key.
  - Past the last entry: the empty list (or undef) once, then it starts over.
  - Entries come in insertion order, as `keys` gives them.
- An array literal flattens `each`, as it does `glob` and `unpack`.
- `keys` and `values` reset the iterator. B::SoN leaves `keys` off the
  control chain (pure), so `each` over a hash whose keys or values isn't
  ordered among its calls is refused by name. Unrefused, it printed 0 where
  perl prints 2.
- Test: llvm-each.t (5 tests; the 4 that test the change failed first).

**Round-tripped:** 021.

**Follow-ups:**
- Producer: B::SoN should order `keys` and `values` (memory and control)
  on a hash that some `each` walks. Then the refusal can go.
- `while (my ($k, $v) = each %h)` hits "a control node with 2 successors"
  (Call, Not). That's a loop shape of its own.
