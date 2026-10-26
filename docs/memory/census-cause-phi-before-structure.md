---
name: census-cause-phi-before-structure
description: 430/430 goal, "Phi node encountered in lower_value before its enclosing structure" (115 210 220) -- three roots: a loop phi read after its arm dropped it (fixed, 220), a back-edge reaching an inner loop's phi (115, now named), a loop driven early (fill1, refused); 257 -> 258
metadata:
  type: project
---

**Cause:** "Phi node encountered in lower_value before its enclosing if/loop
structure" (115 210 220). One message, several roots.

**Built (chalk d75ad368, 355349a7):**
- `_prelower_loop_store_operands`: a store container the pass makes
  (`$r[$i]`) reached the loop phi in the preheader -> lower its
  loop-invariant root; and walk nested loop bodies and arms (older silent
  wrong: `$m[$i][$j] = ...` stores lost, aggregate made again after the loop).
- `_lower_phi` forcing: a loop's OWN phi has the Loop as region (no head).
  Driven only when the loop is ALREADY MADE and carries no memory (220: a
  grep in an arm's value, its phi dropped with the arm's cache). A loop not
  yet made is NOT driven: forced from an early read it ran out of place and
  again in place (probe fill1: pushes twice, "A A C A C"). fill1 stays
  refused -- why its second loop's phi is read early is open.
- `_prelower_condition_mutation_backedges`: a back-edge reaching an
  unlowered (inner-loop) phi is not a condition mutation (115's `last O`
  merge read it); 115 is now refused by its real name -- a jump to an
  enclosing loop (needs cross-level phi wiring).

**Result:** 220 round-trips; 257 -> 258. 115 refused by name (labeled jump),
210 is a string eval (permanent GAP, agreed with perigrin), fill1 open.

**Lesson:** "drive the structure from its phi" is only safe for a structure
that has run and has no effects; re-running effects is a silent wrong.
