# Census cause: arithmetic nothing typed (358 -> 360, pin 08035bfa)

**Cause:** "NumGt numeric comparison over a Unknown operand" held 326:
`my $i = $ENV{N} // 3; print $i = $i - 1 while $i > 0`. The loop phi takes a
Str in, and its back edge is a Subtract nothing typed, because it reads the
phi. So the phi had no repr.

## What changed (chalk 08035bfa)

- **Back edge.** An untyped Add, Subtract, Multiply, Divide or Negate on a
  loop phi's back edge counts as a Num, so the phi is the Scalar both are.
- **Lowering.** `_lower_binop_int` lowers an untyped Add, Subtract or
  Multiply as an Int of Ints, and a Num otherwise, because a Str operand may
  be "2.5". Each operand is brought there by `_emit_coercion` from what it
  is held as. `_lower_as_repr` would go by the operand's Unknown stamp.
- Anything else nothing typed is refused by name.

**Round-tripped:**
- 326;
- 102, `sub f ($x = g()) { $x + 1 }`: the default makes `$x` untyped.

**Probes:** lp1 (a fractional "2.5" counted down) and lp2 round-trip.

## Earlier in the same stretch (no ROUNDTRIP change)

- **Flattened arguments.** See census-cause-flattened-arguments.md.
- **The fork at the loop head, `while (my $n = shift @w)`** (chalk
  ca60ead6). 151 and 195 now stop at a shift of an Int array that may give
  undef. Lowering that needs the assigned variable to hold undef too, or
  `my $x = shift @a; print "[$x]"` would print [0].
