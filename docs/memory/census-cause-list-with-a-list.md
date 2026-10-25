---
name: census-cause-list-with-a-list
description: 430/430 goal, cause "a list with a List in it" (7) — a range of integers flattens to its numbers; B::SoN coerces string range bounds to Int, so numeric-ness is read from the uncoerced bound; ROUNDTRIP 168 -> 170 (with 371) of 431
metadata:
  type: project
---

**Cause:** "a list with a List in it is not lowered -- it would flatten,
and only an array does here" held 7 cases at f657340b, four shapes:
a range with a computed bound `(1 .. $n)` (076), list repetition
`(1, 2) x 2` (081), a slice `@p[1 .. $#p]` (159, 192, 213), and
`\(@a)` (009, 412).

**Built (chalk bddc415e):** a Range of integers in a list is a loop that
appends each number, none when it runs backwards; `"@c"` over one (a
join over the Range itself) builds it first. Test:
llvm-a-range-in-a-list-is-its-numbers.t (failed 4/5 first).

**Caught on the way:** B::SoN coerces BOTH range bounds to Int, so
`"aa" .. $e` looked numeric and printed `0` for perl's `aa ab ac ad`.
perl counts numbers only when a bound IS one (pp_flop's
RANGE_IS_NUMERIC); the bound is read through its Coerce, and two string
bounds are refused by name.

**Result:** 1 of the 7 round-tripped (076). The rest still hit the same
cause, by shape:
- slices: no memory input on Slice, and `for (@n[1..1])` aliases the
  elements a callee then writes (192) -- needs aliasing, not just reads;
- `\(@a)` (a list of element refs) and `x` repetition: unbuilt.

**How to apply:** when a producer coerces an operand "for" a consumer,
the consumer must still read the original's type where perl's semantics
depend on it.
