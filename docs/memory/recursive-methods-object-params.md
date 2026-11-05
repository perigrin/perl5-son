# Recursive subs/methods with reference and object parameters (2026-11-05)

- Chosen by perigrin as the next project after the census reached 411.
- Built (chalk 33a09e83); test llvm-a-recursive-sub-taking-a-reference.t:
  - `_args_from_reads` falls back to Scalar for a read with no single
    scalar coercion. `_sub_has_define` keeps Scalar params for recursive
    subs only.
    - Allowing them for every sub turned many inlines into defines: 6 suite
      failures and wrong probes. The full check caught it.
  - `_call_sub_define` boxes an argument to a Scalar param, and coerces the
    result to a Scalar where the call is one. It also sets
    `_inline_value_repr` so a run-time dispatch can merge it.
  - `_sub_calls_itself` counts a method call named as the sub (its class
    this one or none).
  - `_lower_call_direct` qualifies a package method's name by its target's
    class, and checks `_recursive_sub_info` for `_call_via` (a run-time
    dispatch's choice) too.
  - Body contexts get the program's MOP ($LOWERING_MOP), so run-time
    dispatch works inside a define.
- Works: a recursive tree walk, a method recursing through $self, an
  accumulator recursion.
- Still refused:
  - a recursive sub whose loop merge of its own call is untyped
    (depth(): NumGt over Unknown);
  - a method whose return type is Unknown (T::total).
- pvm 225 goes further but stops at a foreach-alias `exists` used as a
  ternary's condition (a "store while a read waits" refusal).
  - Three 225-only changes were backed out because nothing exercised them:
    an Object subscript read as a ref, a Scalar bound to an Object read,
    and frame-scoped pending reads.
  - Restored frame scoping is safe now that family A is fixed: p56 is still
    refused and p55/57/58 round-trip.
