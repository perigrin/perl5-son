# Census cause: returned lists read as lists and as scalars (363 -> 364, pin 9fcdfc42)

**Cause:** the "return in the caller's context" group (075, 129, 144, 246,
091). Worked: 075.

## What changed (chalk 3f208c58, 9fcdfc42)

- **Length of a List** is the length of it built as an array:
  `return ()` beside `return @c`, counted.
- **A range with an undef bound** is perl's empty `1 .. 0`. An inlining
  for `collect(undef)` lowers the dead `map {..} 1 .. $n`.
- **A list literal element nothing typed** is stored as it was lowered.
- **A list's scalar reading of a value nothing typed** is that value as
  lowered. The producer marks the Coerce from List; `return ($n, $n + 1)`
  read for a scalar is the Add.
- **A Call made for a scalar** is what its inlined value came out as, not its
  list-shaped stamp.

**Round-tripped:** 075.

## Still refused (what they hit next)

- **129**, `return g()` beside `return 7`: the exit merge has no scalar face,
  because neither exit has one. Needs the producer to give a returned call in
  the caller's context a scalar face. Tried: inheriting the caller's want in
  chalk alone does nothing (reverted).
- **144** `// lhs[Scalar -> List]`, **246** lattice TOP, **091** a block eval
  in list context that can die.

**Lesson (again):** `_repr_of` on a node nothing typed is right only after
`lower_value`.
