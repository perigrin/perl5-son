# Cause: a call whose one argument is a ?: of two lists (2026-11-05)

- Cause: "direct call to X: an argument stamped Array flattens into @_". It
  held pvm 145 and 199.
- 145: `g($c ? ($s, $t) : ())` where g writes `$_[1]`. Perl aliases @_ to the
  taken arm's variables.
- Built (chalk c55bfaad): `_lower_call_on_each_arm`. The condition is
  lowered first, then the call is made in each arm's block on that arm's
  elements. To do that, the Call's input list is swapped for the arm's
  elements and then restored. The value is a phi when it is an Int, Num or
  Boolean; any other type is refused by name.
- Only when both arms are ArrayLiterals of scalars. A one-element arm `($s)`
  is not a list in the graph, so it is still refused by name (the TernaryExpr
  write-back cause).
- 199 still refused: `g(@$x)` with a write to `$_[0]` needs @_ aliased to an
  array's slots. It is the same cause with no ?: in it.
- Result: 145 round-trips. Census 398 -> 399.
