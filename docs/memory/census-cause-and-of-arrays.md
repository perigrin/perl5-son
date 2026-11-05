# Cause: `@a && LIST` in list context (2026-11-05)

- Cause: an And whose both sides are Arrays, in list context. It held pvm 089:
  `my @r = @ARGV && sort c 3,1,2`.
- Perl: when @a is empty, the false value is its count, 0, so the result is the
  one-element list (0). Otherwise it is the right side's list.
- Built (chalk 836bb242):
  - Context `_short_circuit_at_merge`: two phis at the merge (which side was
    taken, and the right side's array), then a select between a fresh `(0)`
    array and the right side's.
  - Analysis `_element_repr`: an And/Or element of a literal flattens like a
    Phi or a Call, so `$r[0]` is a Scalar read by its tag. Without it, the
    element read was typed Array and lli rejected the module.
- Probe lesson: run the probe with arguments too. With none, only the left
  path runs; the element-read bug showed only when printing `$r[0]`.
- Result: 089 round-trips. Census 397 -> 398.
