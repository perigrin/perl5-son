---
name: census-cause-builtin-memory-phi
description: 430/430 goal, "'Unknown' is the lattice TOP" (124 217) -- a loop memory phi over a builtin Call (push, a sort with a comparator) was read as an untyped value phi; plus `$s // []` as a reference; 252 -> 254
metadata:
  type: project
---

**Cause:** "'Unknown' is the lattice TOP" in 124 and 217 -- the same root in
both: a loop's memory Phi whose memory input is a BUILTIN Call (a `push`,
a `sort { ... }` that runs code). `_is_memory_phi` counted MemStart, stores,
direct/method calls, nested memory phis -- not a builtin call -- so the phi
went to `_process_loop_node`'s value-phi emission with stamp Unknown.

**Built (chalk 56519d81, 64c5eb28):**
- `_is_memory_phi`: a builtin Call counts when the PRODUCER marks the phi
  `memory` (a value phi may merge a sort's result, so not unconditionally).
- On the way (217's first refusal): `_emit_coercion` Scalar/Slot ->
  ArrayRef/HashRef/ScalarRef/CodeRef checks the tag and takes the payload
  as the pointer; another value exits 255, as `_container_ptr` does for a
  read. `$r->{f} // []` was refused (number readings have no reference).
  A defined non-reference used as a string never reaches it (typed Str).

**Result:** 124 217 round-trip; 252 -> 254.
llvm-a-foreach-over-at-underscore-aliases.t had 124 pinned as refused (TOP);
updated to perl's answer.

**Lesson:** reduce a TOP refusal by bisecting the program (each piece
alone, then pairs): 217 was a sort in a loop + a map over its result --
neither alone failed. The repr trace (cluck at `_repr_to_llvm_type` for
Unknown) names the consumer in one run.
