---
name: census-cause-sort-by-tag
description: 430/430 goal, cause "sort with a STRING comparator over a Array element" (11) — comparator reads each element by its tag; two silent wrong answers in the numeric comparator; memory input taken for an element; MemStart reads unfrozen in straight-line inlining; ROUNDTRIP 149 -> 154 of 431
metadata:
  type: project
---

**Cause:** "sort with a STRING comparator over a Array element" held 11
cases at 80fbca8e.

**What was really wrong:**
- `_emit_slot_out_of_order` compared raw payloads. A numeric sort used
  `icmp` on bits, which puts negative Nums in the wrong order and
  compares Strs by pointer. Both were silent wrong answers on paths the
  census didn't reach.
- A string sort assumed every payload was a Str pointer. Only the
  literal-list path checked that; an Array operand skipped the check.
- Now each element is read by its own tag. A numeric sort compares as
  Nums, or exactly as Ints when both are Ints (perl's `<=>` past
  2**53). A string sort stringifies each value as perl does.
- A sort with `memory_input` carried its memory version as the last
  input, and it was counted as an element.
- `_lower_inlined_effects_then_value` (a callee that is only calls and
  prints) never froze its MemStart reads. `join(sort keys %h)` before a
  call that writes `%h` read the write. The freeze now covers only the
  reads that callee reaches, because an older wire shares one MemStart
  across graphs (inlined-arg-carries-its-repr.t caught that).

**Round-tripped:** 149 -> 154. 098, 099, 189 and 222 work now.

**What the rest hit:** list flattening, i.e. an Array value inside a
list literal ("ArrayRef elem[0] has repr=Array"; 217, 232, 233, 237 and
others). That's the next feature.
