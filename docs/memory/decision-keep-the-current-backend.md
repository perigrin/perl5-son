# Decision: continue on the current backend for now, possibly refactor to T2 later (perigrin, 2026-10-31)

Asked whether the census work uses the two-layer (T1 producer types ->
T2 functor to machine reprs) lowering architecture, the answer was no.

- **T2's status.** Chalk's `docs/plans/2026-09-04-t2-functor-architecture.md`
  is DESIGN. `lib/Chalk/IR/Transform/T2.pm` is called by nothing in
  `lib/`.
- **What the fixes here are.** They are per-site repr decisions in
  `Context.pm`, which T2 is meant to replace:
  - a merge decided from its lowered arms;
  - an int literal widening to Num;
  - a recursive return settled by trial;
  - Slot-boxing an Int shift;
  - `_repr_of` read after lowering.
- **perigrin's answer:** "Keep going this way."
- **Clarified.** The deliberate part is continuing on this path now. It
  is not a judgment that the current backend is the right design. A
  refactor onto T2 may come later.

**How to apply.**
- Keep working census causes in the existing backend, and don't stop
  to build T2 stage 1.
- Don't describe the current backend as the chosen architecture.
- Each such fix is a hand-written decision a later T2 refactor would
  have to absorb, so record that in the cause notes. That keeps the
  refactor's scope visible.
