# Cause: "a scalar deref of a Unknown is not lowered" (pvm 212), partial (2026-11-05)

- Fixed (chalk b90d3d19): reading `${\ EXPR}` where EXPR is not a variable
  (a ternary, a constant, arithmetic, a concat, a coerce or a builtin)
  gives EXPR's value. It is boxed when the deref is stamped Scalar; without
  that, readers expecting a %Slot got an i64 and lli failed.
- Still refused: 212's second sub, which stores through
  `\($c ? $v : 0)` and `\($c ? ($s, $t) : ())`. A store through a
  reference to a ternary of lvalues would need a pointer select between the
  arms' locations.
