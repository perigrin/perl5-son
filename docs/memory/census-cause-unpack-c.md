# Census cause: unpack with a C template (380 -> 381, chalk ccbfa75b)

**Cause:** "join over an operand with repr=Unknown". It held 368:
`my @c = unpack("C3", $s); print "@c\n"`. unpack had no lowering, so its
Unknown-stamped Call reached join.

## What changed

- `_lower_unpack`: a constant template `C`, `C<n>` or `C*` and one
  string. It returns an %Array of Int slots via `@chalk_unpack_c`
  (min(n, len) bytes, zero-extended).
- Wired the way glob is: dispatch, `_emit_array_of`, the flattening
  list builder, and join's flatten rule (an unpack Call is a list).
- Refused by name: other templates, scalar context, and any reader
  other than an array literal, join or a loop.
- Test: llvm-unpack-of-bytes.t (8). Red before: 1-5 and 7.

**Round-tripped:** 368.

**Seen on the way:** element reads (`$c[0]`) of the array refuse. The
producer stamps the elements Unknown, as it does glob's. That's a
producer typing gap: unpack "C" values are Ints.
