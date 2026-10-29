# Census causes: a blessed hash read as Object; a field aggregate assigned whole (354 -> 356, pin 5c60242f)

**Causes and cases**
- **"an inlined argument is a HashRef where the callee reads a Object"**
  held 208 and 224.
  - 208 round-trips in probes.
  - 224 next hits "Phi node encountered in lower_value before its enclosing
    if/loop structure".
- **"a list assignment to a FieldAccess that is not a scalar kept in
  memory"** held 141 and 247.
  - 247 round-trips in probes.
  - 141 is refused by name: its methods return the assignment's value.

## What changed (chalk only)

- **A blessed hash read as Object.** B::SoN stamps whatever a `->new` makes
  as Object, and use-typing carries that to the callee's `$self`. A callee
  node stamped Object but bound to a HashRef, ArrayRef or ScalarRef
  argument takes the caller's value as it is. That is the Unknown path, and
  `_repr_of` hands a reference binding to the node's readers. A real
  `class` object binds as Object and is unaffected.
- **A field aggregate assigned whole** (`@l = LIST`, `%h = LIST`, `%h = ()`)
  is handled by `_lower_field_aggregate_assign`:
  - The list is built as a new aggregate: an array with
    `_emit_flattened_array_of`, a hash as a transient HashLiteral through
    `_lower_hash_ref`.
  - Its header (count, capacity, buffer) is loaded and stored over the
    field's own `%Array` or `%Hash`. The field keeps its aggregate, as perl
    assigns in place, so a reference to it still sees the change.
  - An aggregate field is typed ArrayRef or HashRef, the reference it
    holds; the kind is that type without `Ref`.
- **Its value read is refused by name.** A list assignment's value is a
  LIST: its elements in list context, the right-hand count in scalar
  context. Neither repo types it so:
  - the producer stamps the Assign with its right-hand value's type
    (`@l = (9)` is `Int`) or `Unknown` (`%h = ()`), and method_return_types
    follow (`reset_l: Int`, `reset_h: Unknown`);
  - chalk then made `reset_h`'s return HashRef, apparently from the field's
    type.

  The fix is the sub's two faces: stamp the Assign List, give the Return a
  scalar reading (the right-hand count), and have chalk choose by the
  call's `want`. Both halves are needed:
  - the producer already builds the two faces for a list `return`
    (`_list_return_value`: an ArrayLiteral stamped List, and a Coerce to
    Scalar of the last operand or its Count);
  - chalk chooses only for inlined subs (`return_reading_for_want`). A
    `class` method is one vtable function with one return type, so it needs
    either two entry points (list face and scalar face, picked at the call
    by `want`) or to be inlined when its class is static.

  That is larger than one case justifies now, so 141 is refused until then.
- **`_memory_input_of` and `_value_readers`** are now shared with the
  `can`-as-truth check. A value reader excludes a use as a memory version,
  a memory Phi, and a Region/Loop control input.

## Lessons

- An assignment that is the next statement's memory version is not a
  value read. Every "is its value read?" check needs the memory filter.
