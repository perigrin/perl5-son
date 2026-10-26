---
name: producer-bug-push-loop-memory
description: Producer bug (perl5-son 3bee3a4): a loop whose body only pushes/unshifts got no header memory-Phi, so a read after it read the push inside the body; fixing it re-routed pvm 123 through chalk's drain check (now shift/pop only); a producer change must be followed by a chalk check AND a re-pin, because the census reads the producer live
metadata:
  type: project
---

**Found:** working "an inlined sub's value is made inside one of its arms"
(097 156 205): `sub f { my @o; for my $i (0 .. 2) { push @o, $i } join
",", @o }` -- even this was refused. B::SoN's `_body_stores_memory` knew
shift, pop and element stores, not push/unshift, so the loop had no header
memory-Phi and the join after it read the memory of the push inside the
body. chalk's refusal was right; the graph was wrong.

**Fixed (producer):** push and unshift count. Test
t/wire-a-loop-that-pushes-carries-memory.t (red for push/unshift, splice
already fine). perl5-son suite: only the pre-existing string-eval failure.

**Knock-on (chalk):** pvm 123's fill loop now carried memory and reached
`_prelower_loop_drain_operands`' soundness refusal, written for shift/pop
emptying an array in place. That refusal now applies to shift/pop only.
Also: `Coerce[Array->Num/Int]` is the count, and an inlined callee's @_
under one is a read (`$i < @_`).

**Process lesson:** the census reads the PRODUCER LIVE and chalk at the
pin. A producer change can move a pinned census without any chalk commit:
the pinned f48026ac with the new producer scored 237. After a producer
change, run chalk's check, fix what moved, and RE-PIN even if ROUNDTRIP
is unchanged, so the floor still holds.

**Result:** 238 unchanged (no loss); the probes v2-v9 (C-style for,
while, loops over @_ in a sub) now round-trip. 097/156/205 hit other
refusals next (Phi before structure; a value in an arm).
