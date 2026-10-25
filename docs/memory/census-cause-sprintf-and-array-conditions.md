---
name: census-cause-sprintf-and-array-conditions
description: 430/430 goal, "Call builtin sprintf" (3) + "If.cond[Array->Boolean]" (3) -- sprintf by snprintf per conversion; array truthiness; a frozen element read re-read for its Slot (miscompile); 214 -> 218
metadata:
  type: project
---

**Causes:** "cannot lower op=Call builtin sprintf" (085 086 336) and
"If.cond[Array->Boolean]" (088 089 174).

**Built (chalk 55e5e8fe, aebdae7e):**
- An Array/Hash as a condition: count (field 0 of both) != 0, in
  _emit_coercion and _ensure_i1. 088 round-trips. 089 and 174 now stop
  at `&&` with an Array/Unknown left side.
- sprintf: a constant format parsed at compile time; one snprintf per
  conversion with its own C format (ll for integers, double for floats,
  %.*s by length for strings). `*` widths and precisions come from the
  arguments. Refused: %v %c %n$, a run-time format, and too few or too
  many arguments.

**Miscompile found (already in HEAD):** `_subscript_slot` -- the whole-Slot
read that _miss_kept uses where a miss must survive (a ternary arm, //, a
store, a list element) -- lowered the element read AGAIN where its user
stood. For a read frozen at an earlier memory version, that came after
a later store: `$c ? $h{a} : 8; g($h{a})` (g writes 5 via $_[0]) gave 5
for 1. Fixed by freezing the Slot form too (cache key "slot:<id>"). The
first attempt froze it for reads bound to inlined arguments as well, and
11 suites broke (ArgsSource reached): a bound read is the caller's
value, so it is skipped.

**Lesson:** a speculative eager computation at freeze time must skip
everything the lazy path short-circuits (here, _arg_bind).

**Result:** 214 -> 218.
