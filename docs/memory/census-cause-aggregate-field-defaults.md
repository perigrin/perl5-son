# Census cause: an aggregate field's list default (365 -> 366, pin 8399d361)

**Cause:** "Subscript container has repr=List". It held 153:
`field %items = (r => {7=>"V"}, s => [1,2])`.

## What changed

- **Producer 2edee79.** `_wire_field_defaults` types a computed default
  by the field's sigil. `%` is Hash and `@` is Array. Before, it took
  the type of the list its graph returns. Test:
  t/wire-an-aggregate-field-default-is-its-sigil.t.
- **Chalk 8399d361.** Context.pm, Call(new) default path. A `%`
  field's ArrayLiteral default is lowered as a HashLiteral of its pairs.
  Test: t/bootstrap/ir/llvm-an-aggregate-field-list-default.t.

**Round-tripped:** 153.

**Lesson:** the producer type fix alone turned the GAP into wrong
answers (rc 255, counts of 0). A wire type change can expose a
consumer path that never ran. Run the probes before committing either
side.
