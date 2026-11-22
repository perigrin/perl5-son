---
name: pending-bug-lower-pm-two-shapes
description: CLOSED (wire v2 stage 9b) -- the producer wrote chalk's Target/LLVM/Lower.pm in one of two shapes run to run; it was the loop scouts. The ratchet keeps PERL_HASH_SEED=0, which no longer hides anything
metadata:
  type: project
---

CLOSED 2026-11-22, by wire v2 stage 9b (Braun's construction replaced the
loop scouts). Found in stage 3 (2026-11-20), recorded at the stage 2+3
integration: B::SoN was not deterministic on chalk's
lib/Chalk/Target/LLVM/Lower.pm -- Builder::read_as_a_truth came out in one of
two shapes, and Builder::go_round with one of two refusals, from one run to
the next, under the base producer too.

**Measured at the close** (chalk v2-s9 89317de9, Lower.pm compiled whole):

- the stage 9a producer (006b485, the scouts): PERL_HASH_SEED 1 and 2 give
  one wire, 3 and 4 another -- go_round refused as "a list-context read of an
  array mutated in place has no memory to observe the mutation against" or
  as "a ternary with a multi-element list arm not yet lowered";
- the stage 9b producer (Braun, no scouts): seeds 1 to 6, one wire, byte for
  byte (go_round: the ternary refusal).

So the hash walk whose order reached the graph was the scouts' (their
placeholders for every key in scope, and what a scout that died part way
found). Nothing else was changed for it.

**How to apply:** the ratchet (t/wire-verify-ratchet.t), chalk's
wire-verify.t and tools/wire-braun-proof.pl still compile under
`PERL_HASH_SEED=0`; keep it (a comparison should not depend on a seed), but
a difference that appears only without it is a new bug, not this one. See
a-shared-visited-set-makes-order-matter.md for the earlier one.
