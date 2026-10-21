---
name: a-guard-must-spell-where-it-stands
description: a node added for safety (an exists hole guard) must be spellable for every operand it can meet; one over a call's list made 16 chalk modules INVALID
metadata:
  type: feedback
---

The foreach topic alias guarded holes with `Exists(array, i)`. Over
`@f = values %cache` (bound to the call) and `sort keys %$h`, it was
spelled `exists((values(%cache))[$i])`, which perl rejects at compile
time. IR::Graph was INVALID, and 15 modules that load it failed with it.
Every unit test passed: the tests looped over pad arrays and derefs.

Fix: `_list_may_have_holes`. Only a container (pad array, deref, named
literal, `@phiN` merge, array ref) gets the guard. A list a call made has
no holes.

**Why:** the guard was written for the case under test. The census is
the first place a call-bound array met it.

**How to apply:** when adding a node to a lowering, enumerate the operand
kinds that reach it: ArrayLiteral named and unnamed, PadAccess,
PostfixDeref, Phi, Call, TernaryExpr. Write one test per kind before
running the census. An INVALID count jumping by a dozen is usually one
module that others `use`. Find it with a parallel `perl -c` over the
emissions and grep the first error.
