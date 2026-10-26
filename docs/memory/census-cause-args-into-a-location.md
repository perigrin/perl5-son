---
name: census-cause-args-into-a-location
description: 430/430 goal, "cannot lower op=ArgsSource" (4: 102 154 203 220) -- `my (...) = @_` into a location was lowered as a value of @_; fixed with the 3-arg substr refusal and an older loop silent wrong it exposed; 247 -> 248
metadata:
  type: project
---

**Cause:** "cannot lower op=ArgsSource (not in literal-arithmetic slice)"
(102 154 203 220). Four different roots behind one message; the one
worked: `sub run { my ($in) = @_; g($in) }` -- $in is passed on, so the
producer keeps it in memory and PINS the `my (...) = @_` Assign on the
control chain (an unpinned one is never processed; its targets are just
bound). Processed, `_lower_assign` lowered @_ as a value.

**Built (chalk 560d7ea5):**
- `_lower_assign`: an Assign from ArgsSource with a location target stores
  each target's binding (`_arg_bind`, an unpassed one is already an Undef
  Slot) into its location.
- `_refuse_an_in_place_write_to_a_location`: a 3-argument substr reads;
  only the 4-argument form writes (an lvalue substr arrives as it).
- **Older silent wrong exposed by that:** a location read at a loop's
  memory Phi, consumed only by an unpinned value lowered at the back edge,
  re-read the location AFTER the pass's store (`$o .= $p * 10; $p = g($p)`
  printed 10.20.30. for 0.10.20.). `_lower_loop` now lowers and freezes
  every location PadAccess at the loop's memory Phis in the HEADER (which
  dominates body and exit), before the condition.

**Result:** 154 round-trips; 247 -> 248. Still GAP: 102 (ArgsSource via a
signature default `($x = g())`), 203 (`\$_[0]`), 220 (a Phi before its
structure). Refused, older: nested while loops over a location
(`Phi ... before its enclosing structure`), `while (1) { ... last }`
("could not find loop condition"), `.=`/`//` on an argument target nothing
typed.

**Lessons:**
- Loosening a refusal can expose a silent wrong it was masking: the 3-arg
  substr refusal hid the loop location-read bug. Sweep the shapes the
  refusal used to cover.
- Freezing runs after stores and at MemStart; a loop memory Phi is a
  version too, and nothing froze reads at it.

**Follow-ups in the same group (chalk 597aa371, c5351b72; ROUNDTRIP stays 248):**
- 102 (signature default): a no-argument call bound nothing (Parameter
  "outside an emitted function body"); it now binds through the argument
  path. Arity: a default that runs code has no `default_when` -- perl's
  `mandatory` counts EVERY scalar and the last `optional` take defaults.
  **Wrong answer fixed:** defaults were lowered before the inline frame's
  cache snapshot, so one call's `$y = $x * 3` served the next. Still GAP:
  the merge of an untyped parameter with `g()` is TOP.
- 203 (`\$_[0]`): `_arg_binding` takes a location argument's pointer in the
  CALLER's frame; `\$_[N]` is that. **Caught while building:** resolved in
  the callee's frame (`_local_slots` is per frame) it made a fresh `my`
  and the write was lost. Elements/values refused -- 203 passes a foreach
  alias, so it is refused by name now.
- Lesson: anything an inlined body needs from the caller's frame (a
  location, an aggregate) must be captured at bind time; the frame
  localizes var_table and _local_slots.
