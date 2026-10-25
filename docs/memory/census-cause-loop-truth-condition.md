---
name: census-cause-loop-truth-condition
description: 430/430 goal, cause "could not find loop condition" — a while whose condition is a truth test, not a comparison; any Boolean pinned to the Loop is its condition, and Str/Scalar truthiness is perl's; ROUNDTRIP 176 -> 181 of 431
metadata:
  type: project
---

**Cause:** "could not find loop condition — the loop ir-block must
express the condition as a comparison" for `while (my $next = $P{$c})`
(B::SoN: Not(Not(x)) pinned to the Loop) and `while (defined $cur)`.
chalk looked only for a comparison operator among the Loop's consumers.

**Built (chalk b129e72f):** any Boolean-stamped node whose control_in is
the Loop is the header's condition. A truth test of a Str or a Scalar
(read by tag) goes through _emit_coercion's truthiness arms: "" and "0"
false, "0.0" and " " true, undef false. Test:
llvm-a-loop-tests-its-condition-for-truth.t (failed 3/3 first).

**Result:** 181 at b129e72f (three census runs agree); new since the last
pin: 100 (return-from-a-loop), 139, 241, 256, 307, 373. Still refused on
the condition: 122. 138 now hits `ref()` of an Unknown.

**How to apply:** the producer pins the header test to the Loop; trust
that link before any heuristic over the loop's Phis.
