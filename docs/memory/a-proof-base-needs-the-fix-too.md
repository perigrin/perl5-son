---
name: a-proof-base-needs-the-fix-too
description: "A comparison proof whose two sides share a state bug compares the bug: fix it on both (a throwaway base branch), read every graph not just the first that differs, and probe each 'more precise' row for a wrong answer -- the 9b proof's 17 rows hid three Braun defects and a WRONG"
metadata:
  type: feedback
---

Stage 9b's proof (9a wire vs 9b wire) missed 17 chalk-lib rows, and they were
judged "the 9a wire's leftovers, 9b the more precise" (baseline section 15).
Re-run with the shared bug (%MUTATED_LITERALS by node id) fixed on BOTH sides
(006b485 + fix as a throwaway branch, 6fdb254 + fix), they were three kinds:
the collision (6 rows), two 9a scout marks (2), and Braun's scan (9) -- and
one of the scan's departures hid a silent wrong answer (an array passed to a
call later in a loop body, `1,2 1,2` for `1,2 1x,2`).

**Why:** a fix to shared state moves what both sides do, so a proof run over
the bug compares the bug's two outcomes. "The new side is more precise" is a
claim about values, and only a probe through the backend checks it.

**How to apply:**
- Fix a bug both sides share on both sides before reading a comparison.
- The proof stops at a file's first differing graph: list every graph
  (scratchpad `allg.pl`: the proof without the `last`).
- Take a diff to its seed: own parts of nodes (op, fields, stamp, input ops)
  as a multiset per side; then normalize one suspected cause out of both
  wires (e.g. a PostfixDeref '@' over a literal) and see if the rest is SAME.
- For a cause, trace the producer: a debug copy of lib/ logging the decision
  with `$IN_SCOUT`, the line (`$SoN::IR::NodeFactory::SITE`), the slot.
- For each "more precise" row, write the shape as a probe and run it through
  chalk on both producers (WRONG at one side is the finding).

Related: [[pending-bug-mutated-literals-keyed-by-node-id]], [[a-loop-is-walked-once]].
