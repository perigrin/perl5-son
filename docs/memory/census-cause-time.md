---
name: census-cause-time
description: 430/430 goal, part of "'Unknown' is the lattice TOP" -- time() was unstamped on the wire and unlowered in chalk; producer stamps it Int, chalk calls C time(); 250 -> 252 (065 331)
metadata:
  type: project
---

**Cause:** "'Unknown' is the lattice TOP" (5 cases, different roots). One
root: `time()` -- B::SoN left it Unknown, so `1 + time() * 0` (pvm 331's
fold-defeater) was Unknown all the way down; chalk did not lower it at all.

**Built:** perl5-son 8a6009a adds `time => 'Int'` to FromOptree's
`$FIXED_RESULT` builtin table (t/wire-time-is-an-int.t); chalk faf558ec
lowers it to `call i64 @time(i64* null)` (`_need_time`,
t/bootstrap/ir/llvm-time-is-the-clock.t).

**Result:** 065 331 round-trip; 250 -> 252.

**Lesson:** chalk's Analysis cannot narrow a node the wire stamped Unknown
-- `_join_repr($node->stamp, @inputs)` keeps TOP by design ("Unknown is
reached by absorption or declaration"). An untyped builtin is fixed where
the stamp is made, in the producer, not patched in the consumer (a chalk
Analysis rule for `time` typed the call but not the arithmetic over it,
and was dropped).

**Not taken (yet):** Scalar-container element stores (5: 176 184 225 232
233). Reads through a Scalar exit 255 when it holds no reference; a store
cannot simply mirror that -- `$a[0]{k} = 1` autovivifies the element in
perl, and an exit there is neither perl's answer nor a named refusal.
Needs autovivification into the source (an element, a location) or a
static rule for which containers cannot be undef.
