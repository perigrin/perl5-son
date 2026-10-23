---
name: census-cause-a-sub-ending-in-an-if
description: 430/430 goal, cause 2 — "an inlined sub's value is made inside one of its arms" (48): void calls lower no value, the arm guard walks control back to a Proj; 48 -> 16; ROUNDTRIP 76 -> 77; the rest moved to Assign lhs got MemStart (shared file lexicals)
metadata:
  type: project
---

**Cause:** a sub ending in an `if` makes its implicit value inside an arm.
That value has no merge that reaches the caller, so the inliner refuses it.

**Cases held:** 48.

**Fixes (chalk 0951e88d, 938bdb79):**
- A statement call (B::SoN `want=void`) has no reader. Its effects are
  inlined and its value is never lowered.
- The arm guard refused every effect off the callee's main chain. Now an
  effect counts as "in an arm" only if its control walks back to an arm's
  Proj. A floated call (no control) and a loop phi pass. A merge inside an
  arm stays refused.

**Round-tripped:** 1. ROUNDTRIP 76 -> 77. 16 remain.

**What they hit next:** mostly "Assign lhs ... got MemStart". That is a
store to a file lexical that a named sub closes over (B::SoN `shared`).
That became cause 3.

**Lesson:** the first version of the guard was too strict and dropped
ROUNDTRIP to 75. A guard that refuses must be measured both ways: against
the wrong answer it stops, and against the census it costs.
