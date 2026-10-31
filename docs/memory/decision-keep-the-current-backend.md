# Decision: keep lowering in the current backend, not T2 first (perigrin, 2026-10-31)

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

**How to apply.**
- Keep working census causes in the existing backend.
- Don't stop to build T2 stage 1.
- Each such fix is a hand-written decision T2 would later absorb, so
  record that in the cause notes.
