---
name: census-cause-sub-arguments
description: 430/430 goal, cause 1 — binding sub arguments (my (...) = @_, several shifts, $_[N]): 56 "accesses @_ as an aggregate" -> 21; ROUNDTRIP 76 -> 76; the 35 moved mostly to "value made inside one of its arms" (sub ending in an if, 48)
metadata:
  type: project
---

**Cause:** the inliner bound one argument. `my (...) = @_` was refused,
and a second `shift` was refused on the claim that two shifts hash-cons and
lose their order. They don't: each takes the previous shift as its memory
input, which gives the order. (chalk 73b983bc.)

**Cases held:** 56 ("callee accesses @_ as an aggregate") and 1 (shift
arity). Afterwards 21 remain, behind other shapes (slurpy targets, a
mixture of argument styles).

**Round-tripped:** 0 new. ROUNDTRIP stays 76.

**What they hit next:** most now stop at "an inlined sub's value is made
inside one of its arms" (48). That is a sub ending in an `if`: its implicit
value comes from inside an arm. These are refused because using that value
breaks dominance (case 405, a nested if, failed in lli before the guard).

**Wrong answers found on the way:**
- A coercion that doesn't keep the value. A number pushed through a
  Str-stamped call was rounded to 15 digits; a big integer came back in
  e-notation. Coercions are now limited to `_keeps_value` arrows.
- Restamping a shared callee node misleads every consumer typed from its
  old stamp. Coerce the bound value to the node's reading instead.

**Next:** many of the 48 call the sub in void context (`report(5, 5);`), so
the value is never read. For a call with no data consumer, skip lowering
the value and inline only the effects.
