---
name: census-cause-ternary-scalar-is-foreach-alias
description: 430/430 goal, cause "TernaryExpr with repr=Scalar" (7 cases) — really foreach-over-@_ aliasing; branched Scalar ternary, element refs, ScalarRef in a Slot; reached a heap overflow (store past end) and a non-terminating arm walk; ROUNDTRIP 128 -> 130
metadata:
  type: project
---

**Cause:** "TernaryExpr with repr=Scalar reached LLVM backend" held 7
cases at 38da3e57. All seven are a foreach over an array (mostly `@_`).
B::SoN spells the iterator `exists $_[$i] ? \$_[$i] : undef` and each
read `exists ? $$alias : $_[$i]`.

**Built:**
- A Scalar ternary is BRANCHED, not a select. A select evaluates both
  arms, and dereferencing an alias that wasn't made is a load through
  null. Each arm is lowered in its own block and its cache entries are
  dropped, as an if arm's are.
- `\$a[$i]` is the element's slot. It's bounds-checked and refused for
  an array that may grow (`_array_may_grow`), because growth moves the
  buffer.
- `$$r` over a Scalar checks the ScalarRef tag at runtime. ScalarRef
  joined `_box_payload`'s set (slot-tag-vocabulary.t updated to nine).

**Reached, each fixed with a test that failed first:**
- An element store past the end wrote outside the buffer (heap
  corruption) and a negative index wrote slot -1. It now extends, with
  the gap undef. Backlog 4d7c2e19 closed.
- An If reached again inside its own arm recursed until memory ran out
  (6 GB, case 124). It's refused by name.

**Lesson:** a hang is worse than a wrong answer because no gate catches
it. Run probes under `timeout`. A probe that sits silent is a finding,
not a slow machine.

**Round-tripped:** 128 -> 130.

**Left:**
- 172: try/catch.
- 186: `uc`.
- 191: an element read across a branch-guarded store.
- 187: an alias into an array a store may grow.
- 124: an arm-walk cycle.
