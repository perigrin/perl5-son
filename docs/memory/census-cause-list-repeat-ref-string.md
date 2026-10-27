# Census cause: list repetition, and a reference read as a string

**Causes:** "a list with a List in it is not lowered" (081 list repetition;
372 a string range; 225 a nested ternary) and "Coerce[HashRef->Str] is not
lowered" (225, 141).

**Round-tripped:** 081 (pin 296). 225 next hits the List
ternary; 372 needs perl's magic string increment; 141 is the aggregate-field
list assign.

## What was done

- **(LIST) x N** in a list: the list flattened once, then appended N times
  (none for N < 1). B::SoN wraps the list in a `Coerce` to Str (the scalar `x`
  reading) and Analysis restamps the inner ArrayLiteral as Array, so the
  strip reads the Coerce's `wire_from // from_repr` eq 'List', not the
  input's stamp. A list literal is flattened through its INPUTS: as one input
  it reads as a scalar (its last element, or a count).
- **A reference as a string** (`"$h"`, a hash key) is `KIND(0x...)`, with
  `Class=` in front when blessed: `_emit_to_str` reuses `_emit_ref_reading`,
  the reading a reference in a %Slot already had. Tests compare only the
  shape and equality: the address is not perl's.

## A wrong answer caught by the test (before commit)

`(1, 2) x 2` gave "2 2": the strip tested the input's stamp (Array after
Analysis), so the Coerce stayed and the literal was read as a scalar.

## Lessons

- Analysis restamps nodes; the WIRE's reading of a Coerce lives in
  `wire_from`. Code that recognises a producer shape by its stamps must read
  the wire field, or it sees the narrowed shape instead.

Tests: chalk `llvm-a-list-repeated.t`, `llvm-a-reference-as-a-string.t`.
