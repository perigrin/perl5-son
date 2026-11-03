# Census cause: an array literal of Num and Str elements (390 -> 391)

**Cause:** "an array literal of Num and Str elements is not lowered -- read
as Str, its Nums would lose digits". It held 002: `(42, 0.5, 'plain')`.

## What changed
- chalk ac7d7b32: such a literal stores each element with its own tag, and
  `_element_repr` makes an element read a Scalar when the elements hold
  both Num and Str. The tag decides how it's read.
- B::SoN 5c89120: the same rule in `_literal_element_type`. It used to stamp
  the read Str (the join) and coerce Str->Num for `==`.
- Found on the way (B::SoN 5c89120, older): a number constant was written
  with 15 digits. `0.1 + 0.2` folds to 0.30000000000000004 and reached
  chalk as 0.3, so `$x == 0.3` was true (it should be false). Now written
  %.17g where 15 digits don't read back as the same double.
- Tests: chalk llvm-a-mixed-array-literal.t (3 of 4 failed first; the
  interpolation case already passed). B::SoN
  wire-a-number-constant-keeps-its-bits.t.

**Round-tripped:** 002.
