---
name: census-cause-callee-writes-args
description: 430/430 goal, cause "callee writes $_[N]" (8 cases) — copy-in/copy-out through a real @_ array; reached two pre-existing wrong answers (list assign into locations dropped `targets`; a missed element stored as a defined value); ROUNDTRIP 125 -> 128
metadata:
  type: project
---

**Cause:** "direct call to X: callee writes $_[N]" held 8 cases at
bb10747b.

**Built:** a callee that stores to `$_[N]` (N a constant) binds `@_` to
the array the call builds, and reads it as that array. A positional
binding would read the value from before the store. After the inline,
each written element is stored back to what it aliases: a variable kept
in memory or an element. A write to a literal is refused; perl dies
there. A temporary needs no store-back.

**Wrong answers it reached, both silent and both pre-existing:**
- The list assign `my ($a, $b) = (1, 1)` into variables kept in memory
  is `Assign(t1, t2, v1, v2)` with a `targets` count. Chalk's loader
  dropped the count, so it lowered `t1 = t2`. Now it stores pairwise,
  reading every value before any store.
- A missed element read stamped as the container's values (a missing
  key read as Str) was stored as a defined `""`. Every Slot store site
  keeps the read's own Slot now (`_miss_kept`). The baseline crashed
  lli on this case.

**Lesson:** an unblocked cause reaches code no census case ever ran.
Probe what it reaches, not just the cause's own cases. Both wrong
answers came from probes written on the way.

**Round-tripped:** 125 -> 128.

**What the rest hit:** `sprintf` (085), a list in `@_` (145), a
TernaryExpr over Scalar (186), Slice (192), `lock` (008), and a lexical
sub with `s///` on its argument (112).
