# Census causes: untyped merges, loop phis, a few builtins (329 -> 334)

**Causes worked:** single-case refusals left after the use-typed parameter
work -- "shift of an Int array read by a Coerce" (018), "join over an
operand with repr=Int" (216), "push onto a Unknown" (140), "ref() of a
Unknown" (221), "a loop phi read as a Scalar carries a HashRef" (138),
"Region.Phi/TernaryExpr/// [X -> Unknown]" (073, 226).

**Round-tripped:** 018 140 221 (332 at chalk 8d9c59af), 073 226 (334 at
9f561b80). Next hits: 216 an if reached again inside its own arm; 138 a
reference to a constant (`\1`); 215 a Region phi with an arm nothing
typed; 143 And.LHS, 180 grep test, 204 ListAppend over Unknown; 326/169 a
loop of arithmetic over an untyped phi (needs typing arithmetic without
its operands -- refused rather than risk Int/Num precision).

## The rule that kept recurring

A node nothing typed (stamped Unknown) is what its arms or its argument
make it *at this lowering*: one repr if they agree, a Scalar each arm is
boxed into if they differ (scalars or references). Applied to: a Region
phi (refs now allowed), a jump merge, a loop phi (both values; arrays and
hashes stamped, since an array variable is one at every inline), a loop
exit merge (each arm boxed in its own block; an Undef arm needs no value),
a ternary (by_slot), a `//` (definite lhs -> lhs; undef lhs -> rhs; Scalar
lhs -> by its defined bit). Consumers that ask a node's repr before it is
lowered (a deref, ref(), a ternary's arms) lower it first.

## Miscompiles found (reported)

- A match in list context assigned to a list took the match's truth: `my
  ($c,$s) = "A::b" =~ /(.*)::(.*)/` gave "1 ". Now captures where it
  matched, undef where it missed; `defined` of a list-assigned variable
  reads its cell's defined bit (a Str-stamped `$c` read "always defined").
- A Count through a value read by its tag was frozen ahead of the `ref $r`
  that guarded it and exited 255 -- now it waits where it is used, as an
  element read does.

## Lessons

- Each newly lowered shape exposed the next layer's stamp reads; a wrong
  answer appeared twice (073 exit 255, 226 "1 |"), both caught by probing
  the case before the check. Probe every case a change touches.
- Test sources with single quotes break `qx($^X -e '$src')`: write them to
  a file.
