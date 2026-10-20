---
name: tbase-9-of-9
description: t/base reached 9/9 on 2026-09-01; what the last file needed and what it cost
metadata:
  type: project
---

**t/base is 9/9** as of 2026-09-01 (commit 202a418). `base/lex.t` was the last
holdout and translates with zero GAPs.

Corpus across base+cmd+comp: **OK=22 GAP=13 INTERNAL=4**.

lex.t took FOUR distinct fixes, and only the first was the one its GAP named:

1. `substr` arity — OpMap declared a fixed pop_count of 2 for a 2-, 3- or
   4-argument op, so `substr($s,1,3)` dropped the STRING and kept index+length.
   The stray stack value is what made the `s///e` replacement look like "not a
   single value". A silent miscompile underneath a correct-looking refusal.
2. Scalar deref READ — `PostfixDeref` was dead vocabulary (registered,
   serialized, built zero times), so `${\ EXPR }` refused.
3. Scalar deref WRITE — `$$r = 5`. The demotion machinery already existed
   (`_address_taken`, reads carrying a memory version, `Assign` stores); the
   lvalue rv2sv just had to yield the location and let sassign's element-store
   branch handle it.
4. `AnonSub` missing from the map-contribution allow-list.

**Why:** the GAP message named the s///e handler, which was correct about what
it observed and wrong about the cause. Chasing the message rather than the
construct would have produced a fix in the wrong file.

**How to apply:** when a refusal names a handler, check whether what it caught
is an upstream operand leak before touching that handler. Three of these four
were one layer below where the error surfaced. See
[[read-generated-output-not-tests]] and [[allow-lists-fail-asymmetrically]].
