# Cause: "dispatch: X has repr=, which has no i64 payload encoding" (2026-11-05)

- Held: pvm 198. `$_->set_stamp(undef) for @stale`, a method dispatched on a
  run-time class and called in void context.
- The dispatch arm coerced the inlined value (no repr) to the merge's
  Scalar and refused.
- Built (chalk 5fe682b5): a void call whose value has no repr merges an undef slot.
  A used value with no repr is still refused (y2d: "push of a Unknown").
- Result: 198 round-trips. Census 406 -> 407.
