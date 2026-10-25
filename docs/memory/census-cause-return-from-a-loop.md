---
name: census-cause-return-from-a-loop
description: 430/430 goal, the "Phi node before its enclosing structure" cases that were a `return` inside a loop — a jump merge (one ordinary way in, arms that jump in from inside); ROUNDTRIP 175 -> 176 of 431
metadata:
  type: project
---

**Cause:** after the eval work, "Phi node encountered in lower_value
before its enclosing if/loop structure" (7) and "an inlined sub's value
is made inside one of its arms" (6) shared a shape: a `return` inside a
loop of a sub chalk inlines (069, 100, 138, 139, 173 ...).

**The shape:** B::SoN joins the return with the loop's own exit at the
sub's Return: a Region with no head, whose inputs are one ordinary way
in (the loop's exit Region) and arms that jump in from inside the loop.
An arm's input is its LAST statement (a store before the return), but
the merge Phi's `predecessors` names it by the arm's Proj -- match both.

**Built (chalk 9a9e4dda):** the chain builder recognises a JUMP MERGE --
every input but one walks back to an If's Proj whose If is NOT on the
one input's own chain (a try/catch merge's If is, which keeps it out) --
and lowers it where it stands. Each arm lowers its value in its own
block and branches to it; the ordinary way in joins them.

**Result:** 1 round-tripped (100); 138 and 139 then hit the loop
condition (census-cause-loop-truth-condition), the rest other causes:
an inlined value made in an arm (069, 097, 155, 156, 173, 205), a
labelled `last O` in a nested loop (115), try/catch (172), a string
eval (210).
