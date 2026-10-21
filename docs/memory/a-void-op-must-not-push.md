---
name: a-void-op-must-not-push
description: A stale stack slot under a sub's body becomes its return value when the last statement pushes nothing
metadata:
  type: feedback
---

`sub g ($k, $x) { if ($k) { 1 } else { $h{$k} = 3; 2 } }` returned `$x`
(`XY` for `12`), in baseline too. The void `argelem` pushed its Parameter
and nothing popped it; the if/else, unable to merge an element-store arm's
value, pushed nothing, and leavesub took the leftover.

**Why:** "WANT 0 pushes nothing" is safe only because the deparser then
spells the if/else as the sub's last statement and perl yields the value
itself -- which needs a clean stack AND an arm whose last value is the
store. An arm yielding something after its store (`{ $h{$k}=3; $h{z} }`)
lost that read in the spelling.

**How to apply:** a handler for a void op (flags & 3 == 1) pushes nothing.
When a miscompile returns an argument or an earlier value, look for a
stack leftover before looking at the construct. An element-store arm may
merge a later value that reads no memory (_value_reads_no_memory); one that
reads memory refuses in the caller's context.
