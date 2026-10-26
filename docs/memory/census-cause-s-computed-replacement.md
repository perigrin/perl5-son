---
name: census-cause-s-computed-replacement
description: 430/430 goal, "s/// with a computed replacement" (3: 200 288 289) -- the producer computes the replacement in the match's arm; chalk splices that value in; 200 289 round-trip (238)
metadata:
  type: project
---

**Cause:** "s/// with a computed replacement is not lowered -- only a
literal one" (200 288 289).

**Shape:** B::SoN lowers `s/(y)/<$1>/` (or `s/a/$n+1/e`) as RegexMatch ->
If -> the replacement computed in the then-arm (RegexCapture, Concat, the
/e expression) -> a Phi with undef -> RegexSubst(subject, that Phi, mem)
with `replacement` "". A plain `s/a/$y/` is folded to a literal upstream.

**Built:** `_lower_regex_subst` takes the operand as a `val` segment: in
the matched block it is lowered, read as a Str, and memcpy'd where the
match was; `/e` is accepted only with such an operand (the producer did
the evaluating). The result phis now name `$lbl_do_end` -- the block
current at the branch -- because reading a Scalar replacement by its tag
opens blocks (the loop-exit lesson again: never name a label captured
before lowering as a predecessor).

**Result:** 200 and 289 round-trip; 288 next hits `(?{ ... })` code in a
regex. Probes (loop, sub, /e calling a sub, no match, hash lookup, \U)
round-trip or refuse by name (`$&` refused: no legal global name).
