---
name: census-cause-at-underscore-as-a-list
description: 430/430 goal, cause 7 — "callee accesses @_ as an aggregate" (21): @_ read as a list is an %Array of the call's arguments; ROUNDTRIP 84 -> 89; three wrong answers (loop phi values not read as the phi; Int/Num and Int/Str array literals read raw)
metadata:
  type: project
---

**Cause:** an inlined callee reading `@_` as a list: `for my $x (@_)`,
`"@_"`, `scalar(@_)`, `join`. Cause 1 had bound only positions.

**Cases held:** 21.

**Fix (chalk 46b6f7db):**
- Read as a list, `@_` is an `%Array` of the call's arguments, built at
  the call.
- A copy can't carry a write back to the caller, nor a shift out of the
  list. So a store to `$_[N]`, a reference to one, a shift before the
  list read, a builtin that may write it, and an argument that would
  flatten are all refused by name.

**Round-tripped:** 5 of the 21. ROUNDTRIP 84 -> 89.

**What they hit next:**
- 6 stop at an `Exists` consumer of `@_`.
- 3 stop at a sub ending in an if.
- 2 stop at `my %o = @_` (a HashLiteral).
- The rest are one each.

**Wrong answers found on the way, each red first:**
- A loop phi's two values weren't read as the phi is. An Int 0 went into
  a double phi, and an undef's defined bit and an i64 counter went into a
  `%Slot` phi (backlog 22f3248c, pvm case 106). Both ends are now coerced;
  a mismatch with no exact coercion is refused.
- Mixed array literals were read raw by the join's stamp. `(1.5, 2)` read
  the 2 as 9.88e-324, and `(1, "x")` read the 1 as a string pointer and
  crashed. Ints are now stored as the join (exact); Nums among Strs are
  refused. This is pre-existing, and the hash version was found in cause 5.

**Lesson:** a value's machine type comes from its own node, and its
reading from its consumer's stamp. Wherever the two can differ (a phi
edge, a literal's element, a hash entry), coerce or refuse. Each time I
looked at one, the other side was wrong too.
