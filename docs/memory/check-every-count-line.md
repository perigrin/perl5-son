---
name: check-every-count-line
description: `corpus-roundtrip.pl | tail -2` showed ROUNDTRIP and hid the DIFFERS line above it; a failing case went unnoticed for five batches
metadata:
  type: feedback
---

A corpus case added for `local` in a bare block failed from the moment it
was added -- the `keys %$self` read inside the block was spelled after the
restore -- but every report was `... | tail -2`, which printed
EMITS_INVALID_PERL and ROUNDTRIP and cut off DIFFERS 1 above them.

**Why:** the summary lines are only printed when nonzero, so the last two
lines look the same whether or not a case differs.

**How to apply:** grep for every count line (`^cases|DIFFERS|INVALID|
ROUNDTRIP`) and check ROUNDTRIP equals cases. The root defect was general
(baseline too): a hash read through a reference by `keys` had no
stale-read rule; the list-through-reference pass now takes `%` with keys.
