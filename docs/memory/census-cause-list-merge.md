# Census cause: a merge of lists (Region.Phi -> List)

**Cause:** "cannot lower Region.Phi.then/else[Array->List]" / "[Int->List]"
(077, 090, 129, 144).

**Round-tripped:** 077 (chalk work pending check g152; pinned when it passes). 090 is a producer gap: `my ($x,$y) = $c ? f() : ()`
leaves the list Assign off the control chain, and the `$x`/`$y` reads carry
no VarDecl (chalk refuses by name). 129 and 144 next hit a sub's list return
read in scalar context (`Coerce[List->Str]`): `return g()` takes the CALLER's
context, which is not modelled.

## What was done

- List is a shape with no machine type, so a phi over lists cannot be typed.
  A Phi stamped List is lowered as the chosen ARRAY: each arm is flattened
  (`_emit_flattened_array_of([$arm])`) in its own tail, with the branch's
  variables in scope (`_lower_arm_in_tail` takes an optional lowering coderef),
  and the phi is `%Array*`, recorded as `repr:<id> = Array` (the same cache key
  the Unknown-phi resolution uses).
- Consumers: `_emit_flattened_array_of` appends a merge lowered that way;
  `join` flattens a List Phi (B::SoN aliases `"@a"` to the merge itself).

## Lessons

- A value with no machine type can still be MERGED if every consumer reads it
  through one materialised form. Pick that form at the merge, and teach the
  readers to recognise it, rather than giving the shape a type.
- B::SoN aliases an array variable to the value assigned it: a read of `@a`
  after `@a = $c ? ... : ...` is the merge node itself, not the ArrayLiteral.

Test: chalk `llvm-a-branch-chooses-a-list.t`.
