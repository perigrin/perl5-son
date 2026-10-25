---
name: census-cause-next-in-an-arm
description: 430/430 goal, cause "a `next` that skips the rest of a loop body from an if arm" (5) — a latch block that every pass-ending path meets; B::SoN nests one latch Region per `next`; ROUNDTRIP 170 -> 175 of 431
metadata:
  type: project
---

**Cause:** "a `next` that skips the rest of a loop body from an if arm
is not lowered -- it needs a branch to the loop's latch" held 5 cases at
f657340b (007, 095, 114, 116, 117). One `next if C` alone was already an
ordinary if/else; a second one, or one in a nested arm, was refused.

**The shape:** B::SoN builds one Region per `next`, headed by the Loop
(not its exit), each merging the one before it. The loop's back-edge
Phis are Phis of the last; a Phi of an inner one is opened through it.
The test for "not the exit" is the LOOP's exit Proj (index 1 of the
Loop), not any index-1 Proj -- an if's else arm is index 1 too.

**Built (chalk eb13fca6):** each next-arm lowers what it brings to the
latch Phis in its own block, then branches to a latch block; the body's
end goes there too; the latch merges them and the back-edge leaves from
it. A block left with no path (the last if's arms both `next`) is
`unreachable`. Values lowered for one arm are dropped from the cache
after it, or a later arm reused them where they did not dominate.

**Also fixed, reached for the first time (114):** a `last` arm's value
for a live exit Phi was lowered in the exit block, after the Phi; it is
lowered in the arm, and the recorded break block is the one that
branches (after what the value opened, e.g. a stringify loop).

**Result:** 5 of 5 round-tripped (170 -> 175; three census runs agree).
Probes: nested loops and `next OUTER` are refused by name.

**How to apply:** record a predecessor's label AFTER lowering what it
contributes -- lowering can open blocks.
