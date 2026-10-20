---
name: a-snapshot-walk-keeps-only-its-value
description: "walking a subtree on $sim->snapshot and returning just the popped value silently drops its effects (control, memory, bindings); two instances found 2026-09-29"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-09-29T12:48:22.474Z
---

A helper that walks a subtree on `$sim->snapshot` and returns only `pop_node`
throws away everything else the walk did: control it advanced, memory it
stored, bindings it rebound. Nothing refuses -- the graph just lacks the effect.

Two instances in one session (2026-09-29):
- `_walk_subst_replacement`: `s/b/$n++/e` left $n unchanged; s///ee's eval
  Coerce hung off control ("a control node with 2 successors"). Fix: an
  effectful replacement is the taken arm of an If on the match half, merged back.
- `next if` rest arm walked with `$exits = undef`: a `return` there popped its
  value and built nothing (corpus 008, pick(50) -> "none" for "big-2").

**Why:** the snapshot exists to isolate the stack, but it isolates the effects
too, and the caller only looks at the value.

**How to apply:** when a walker takes a snapshot, ask what the walk can DO
besides push a value, and where each of those goes back to. Test with a
side-effecting body (`$n++`, a print, a return), not a pure expression. See
[[read-generated-output-not-tests]], [[a-silent-drop-is-worse-than-a-refusal]].
