---
name: a-method-call-has-no-ex-list
description: entersub's first kid is the pushmark for a method call, an ex-list for a sub call; a scan of "the args" must take both shapes
metadata:
  type: feedback
---

`_address_taken` demoted a sub call's pad-scalar arguments (perl passes by
alias) by walking `entersub->first->first` and its siblings. For a method
call entersub->first IS the pushmark, which has no kids, so no method
argument was ever demoted: `$o->m($x)` with `sub m { $_[1] = 9 }` died
"Modification of a read-only value" in the emission (baseline too).

**Why:** the two call shapes differ by one ex-list level, and the test
corpus only wrote `$_[0]` through sub calls.

**How to apply:** when scanning a call's arguments, branch on the first
kid's name. Leave a method call's invocant a value -- dispatch and stamp
inference read its class (four tests broke when it was demoted). Demoting
more arguments makes more reads named; the deparser's list-assign target
count then trusted only a target list with no scalar in it.
