# Census cause: references and undef in Scalar fields; ADJUST with branches

**Causes:** "Call(new) X field declared repr=Scalar but constructor argument
repr=ArrayRef/HashRef" (126, 244, 118), then "field value repr=Undef cannot be
stored" (244, `field $left :param = undef`).

**Round-tripped:** 244 (293 -> 294 at check g151). 126 next hits a code reference used
as a value; 118 a method absent from a class vtable (a plain package in a field).

## What was done

- **A reference in a Scalar field.** The store tags the cell with the
  reference's kind, so ArrayRef/HashRef into a Scalar field is coherent
  (`_field_store_is_coherent`). The read side (`_emit_read_slot_as` to Scalar)
  dropped every reference tag onto the undef arm; it now keeps the cell as it
  is. Without that, the deref after it stopped the program (exit 255).
- **An undef default** is no default: the cell starts undefined.
- **A field that may start undef** (an undef default, or neither a default nor
  a :param) is not narrowed by its constructor argument or its ADJUST store
  (`_may_start_undef`); a store makes it Scalar. Narrowed to Int, an Int read
  ignores the defined bit: "d0" for perl's "u".
- **ADJUST bodies are lowered along their control chain** from their Return,
  as method bodies are. They were a flat list of statement nodes, and a store
  inside a branch (`$l //= 5`) was not in it.
- A method returning Scalar whose body is a Num boxes the Num's bits, tag Num;
  a Scalar method call stamped Num reads the cell by its tag.

## Wrong answers found (pre-existing, in the report list)

- `field $l; ADJUST { $l //= 5 }` printed 0 (perl: 5): no ADJUST was emitted
  at all. Now refused by name (the method call's stamp), not wrong.
- `field $l :param = 3; ADJUST { $l += 5 }` emitted invalid IR (LLI_FAIL).

## Lessons

- A probe of a neighbouring shape (op-assign in ADJUST) found two existing
  miscompiles. When a fix touches how a construct is typed, probe its siblings
  (`//=`, `+=`, if/else) against HEAD, not just the case in hand.
- "May be undef" is a property of the field's lifetime, not of any one store:
  every narrowing pass (constructor argument, ADJUST store) must ask it.

Tests: chalk `llvm-a-ref-in-a-scalar-param-field.t`,
`llvm-adjust-runs-its-branches.t`.
