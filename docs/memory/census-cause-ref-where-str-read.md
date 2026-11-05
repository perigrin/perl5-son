# Cause: "an inlined argument is a ArrayRef where the callee reads a Str" (2026-11-05)

- Held: pvm 082. describe() is called with strings and once with [1].
  B::SoN types `$value` Str, and one node feeds `ref $value`,
  `$value gt "m"` and `$str = ... $value`.
- Coercing ArrayRef to Str at the bind would make `ref` answer "", so it
  was refused.
- Built (chalk c45e86b4):
  - A Str-typed read bound to a caller's reference returns the reference
    itself, as a Scalar-typed read of one already did. `_repr_of` gives
    every reader the reference, and each reader converts it as it reads one.
  - `_str_compare_operand` stringifies a reference operand (KIND(0x...)).
- Probed: eq, ne, =~, a hash key, substr, lc, x, sprintf, interpolation,
  length and .= all match perl.
- Result: 082 round-trips. Census 410 -> 411.
