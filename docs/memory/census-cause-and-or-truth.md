---
name: census-cause-and-or-truth
description: 430/430 goal, "And" (4) -- && / || test a Str/Num/Scalar left side by perl's truth; xor; an aggregate left side stays refused (count, not the array); 222 -> 225
metadata:
  type: project
---

**Cause:** "And (&&) LHS operand has repr=X" (089 174 254 255).

**Built (chalk b0ce727c):** _shortcircuit_i1_cond defers to _ensure_i1 for
Str/Num/Scalar (the same truth an if takes), and Xor is xor i1 of both
sides' truth. 254 and 255 round-trip.

**Kept refused, on purpose:** an Array/Hash left side. `my @r = @ARGV &&
sort ...` gives @r = (0) when @ARGV is empty: && evaluates its left side
in scalar context and yields that COUNT. Merging the array would give an
empty list -- and it also produced invalid IR (089). 174 is an Unknown
left side.

**Guard test updated:** llvm-bool-truthiness-guard.t asserted And(Num,Num)
was refused; it now checks `fcmp une double` and a double merge phi.

**Result:** 222 -> 225.
