# Cause: a method returning `values`/`keys` of a field (2026-11-05)

- Cause: "'Unknown' is the lattice TOP" in a class method. It held pvm 246
  (class-feature.md): `method classes { return values %classes }`,
  called in both list and scalar context, after a `->add->add` chain.
- Perl: `return values %h` takes its caller's context: the list in list
  context, the count in scalar context.
- Built (chalk 15a3064f):
  - Analysis %LIST_VALUED_METHOD, for a method whose Return value is a
    values/keys builtin with no `want => scalar` (so not
    `scalar(keys %h)`, which is always a count). Its field is declared
    `%` (looked up through the MOP's fields, since an unstored field is
    stamped Unknown).
  - It covers every method graph, called or not, since every method body
    is compiled.
  - Its calls are stamped Array (want list) or Int (scalar). The method's
    ABI is %Array*. A scalar-context call loads the count, which the
    vtable check allows for list-valued methods.
- Caught by the suite: a `scalar(keys %h)` method was first taken as
  list-valued (llvm-a-method-in-scalar-context-only.t).
- Still refused: a field hash nothing stores to (untyped), and a sub
  storing an object into a shared lexical.
- Result: 246 round-trips. Census 396 -> 397.
