---
name: a-silent-drop-is-worse-than-a-refusal
description: the sassign catch-all else swallows unmodelled targets; measure the corpus cost, then refuse
metadata:
  type: project
---

The sassign handler ends in `else { $sim->push_node($value) }`. Any target
kind with no branch above it lands there and the STORE IS DROPPED while the
graph reports success. `*FH = shift` did exactly that: the glob assignment
disappeared and base/rs.t read from an unopened handle.

**Why:** a GAP costs a file, a drop costs trust in every file. The graph
claiming to have translated a sub it silently mutilated is the one outcome
this project treats as unacceptable.

**How to apply:** before turning a drop into a GAP, measure what the refusal
costs across t/base, t/comp and t/cmd -- a refusal that kills `__PROGRAM__`
in many files can be worse than the bug. For the glob case four files named
the new GAP and none lost a round-trip: two were sub-scoped (strictly better
than a drop), one already lost `__PROGRAM__` to a different GAP, and one
already DEPARSE-GAPped. That measurement is what makes the refusal defensible,
not the principle on its own.

Related: [[crashes-mask-gaps]], [[clean-counts-cannot-measure-progress]].
