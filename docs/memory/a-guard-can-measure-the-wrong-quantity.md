---
name: a-guard-can-measure-the-wrong-quantity
description: "A refusal keyed on a symptom (stack depth) passes or fails on an unrelated property; vary the body, not just the construct"
metadata: 
  node_type: memory
  type: project
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-17T14:23:15.708Z
---

`leaveloop` in a branch arm refused on `stack_depth < 2`. That measured STACK
RESIDUE from repeated body walks, not anything about the loop:

    if ($c) { for (1,2) { $s += $x } }    leaves 1 per walk, depth 3, passed
    if ($c) { for (1,2) { print "x" } }   leaves 0 per walk, depth 1, refused

Confirmed both ways: `print; $s += $x` passed, `print; print` failed. Root
cause was one line -- OpMap says `leaveloop => [2,...]` and the main walk
never reaches _step for it, while a branch arm did.

**Why:** the guard was added to convert a real "Stack underflow" crash into an
honest refusal, and it does that correctly. But a symptom-keyed guard admits
or rejects cases on a property unrelated to the actual defect, so the set it
refuses is arbitrary.

**How to apply:** when probing whether a construct translates, vary the BODY
as well as the construct -- at minimum one pure-value body and one that
advances control (`print`, `warn`). `t/from-optree-loop-in-arm.t` pinned
loops-in-arms with `$n = $n + $i` and missed this for months; my own probe
used `$s += $i` and I wrongly recorded "did not reproduce". Also: bypass a
suspect guard once to see the underlying failure -- it tells you whether the
guard or the thing beneath it is wrong.

Related: [[crashes-mask-gaps]], [[clean-counts-cannot-measure-progress]],
[[the-discriminating-property-is-arity]]
