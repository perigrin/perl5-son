---
name: pending-bug-lower-pm-two-shapes
description: PENDING BUG -- the producer writes chalk's Target/LLVM/Lower.pm in one of two graph shapes run to run (also at base); the ratchet and the downgrade test pin PERL_HASH_SEED=0 around it
metadata:
  type: project
---

PENDING, NOT FIXED (found in wire v2 stage 3, 2026-11-20; recorded at the
stage 2+3 integration, 2026-11-21). B::SoN is not deterministic on chalk's
lib/Chalk/Target/LLVM/Lower.pm: Builder::read_as_a_truth comes out in one of
two shapes, and Builder::go_round with one of two refusals, from one run to
the next. It happens under the base producer too, so it is older than wire
v2. Two runs of the same tree differ by it alone.

**Why it matters:** the verifier ratchet and t/wire-v2-downgrades-to-v1.t
compare counts and wires run to run. With the hash order free, a count can
move with no change at all; with chalk held per graph, Builder's rows would
flap.

**How to apply:** until it is fixed, every place that compiles wires for a
comparison runs the producer under `PERL_HASH_SEED=0 PERL_PERTURB_KEYS=0`
(t/wire-verify-ratchet.t does; t/wire-v2-downgrades-to-v1.t did until stage 6), and a record
is made the same way. The seed hides the bug; it does not fix it. To fix:
compile Lower.pm under several seeds, diff the two Builder graphs, and find
the hash walk whose order reaches the graph (see
a-shared-visited-set-makes-order-matter.md for the last one).
