# Cause: "Call(method) X has no class_name" (2026-11-05)

- Held: pvm 204. `for my $ctrl (@seeds) { while (defined $ctrl) { ...
  $ctrl->id ...; $ctrl = $ctrl->prev } }`. The invocant is a loop Phi
  that was Unknown, so the run-time dispatch had no way to read it.
- Three fixes (chalk c57cab4e):
  - Analysis `_type_run_time_method_calls`: a method call with no class,
    made for a value (want not list or void), is stamped Scalar when every
    package sub of its name returns a Scalar.
    - The first try also covered void calls, and that broke 198 (an LLI_FAIL
      phi of a bare 0). The full check caught it.
    - Use `_is_narrowed`, not `defined ->stamp`: is-narrowed-guards.t
      lints for it.
  - `_writes_list_separator`: a method dispatched at run time walks every
    candidate sub's graph, not just "an unknown callee may write $\"". This
    was found via z2, a pre-existing refusal.
  - `_prelower_condition_mutation_backedges`: a back-edge that is a
    non-builtin Call is never hoisted into the loop header. It ran on the
    final pass's undef and exited 255 before the condition, a silent wrong
    exit.
- Tried and removed (not load-bearing): accepting an Object tag as a reference
  in `_dispatch_invocant`.
- Result: 204 round-trips. Census 407 -> 408.
