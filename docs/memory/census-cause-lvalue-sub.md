# Census cause: a store to an :lvalue sub's call (371 -> 372, pin 0cd45d79)

**Cause:** "Assign lhs must be a PadAccess(VarDecl), VarDecl, or
Subscript(lvalue); got Call". It held 398:
`sub slot :lvalue { $slot } slot() = 42`.

## What changed (chalk 0cd45d79)

- An Assign whose left side is a direct, argument-less Call stores to
  the callee's returned variable. The callee's whole body must be
  `return <shared $ PadAccess>` (`_lvalue_sub_variable`).
- The store then takes the existing shared-lexical path, so the
  callee's later reads see it.
- Any other :lvalue body is refused by name (`GAP: a store to a call
  of ...`). The old message had no `GAP:` prefix.
- The wire also ships `lvalue: 1` on the sub. It isn't needed: perl
  compiles `f() = ...` only for an :lvalue sub.

**Round-tripped:** 398.

**Seen on the way:** the producer refuses `n() = n() . "c"` (a
multiconcat storing into a stacked destination). Producer GAP, not
worked.

## Looked at, not worked

- **385:** `pos($param) = N` plus `/\G($pattern)/`. Run-time regex and
  `\G` are both unlowered, so it belongs to the regex class.
- **141:** `method reset_h { %h = () }` read for its value. One method
  value would need two faces (the count in scalar context, the
  elements in list context). Same class as 129 and 091: the producer
  needs a context face.
