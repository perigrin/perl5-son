---
name: census-cause-push-of-a-reference
description: 430/430 goal, "push of a ArrayRef/HashRef/ScalarRef value is not lowered" (194 198 219 230 140) -- push boxes a reference by its tag; three older silent wrongs found on the way (a named array in a list, a reference read by tag as ""/0, \$x of a my a loop renews); 246 -> 247
metadata:
  type: project
---

**Cause:** "push of a ArrayRef/HashRef/ScalarRef/Unknown value is not
lowered" (194 198 219 230) and "push onto a Unknown" (140).

**Built (chalk 1e50ca25, producer 5d084b6):**
- `_lower_builtin_push` appends a reference as its Slot, tag and all
  (`_slot_fields_of_value` already boxed every ref repr).
- `_element_repr`: a named array (PadAccess stamped Array) in a list
  flattens -- read as Scalar by tag, like a Call/Phi/ternary. `map { } @r`
  over a pushed-to array read each element as a nested %Array* and lli
  rejected the module; **older, Ints too** (`push @r, 5; map {$_+1} @r`).
- `_emit_read_slot_as`: a reference tag read as Str/Int/Num is what perl
  reads -- `KIND(0x..)`, `Class=KIND(0x..)` if blessed (`_emit_ref_reading`,
  snprintf), its address as a number; `_emit_coercion` ArrayRef/... ->
  Int/Num is `ptrtoint`. **Older silent wrong:** it read as undef, so two
  references were one hash key ("") and `==` each other (0).
  Object (class instance) still reads undef -- `shortcut:` in the code.
- Producer marks `\$x` of a `my` a loop renews each pass (`fresh_each_pass`
  on Ref, via `_renewed_per_pass(..., with_iter => 0)` -- a foreach var is
  an alias, not marked); chalk refuses a marked Ref. **Older silent wrong:**
  one location per lexical, every pass's ref named the last (219 printed
  2,2 for 1,2; `$l[$i] = \$x` and `map { my $x; \$x }` too).

**Result:** 194 round-trips; 246 -> 247. 219 now refused by name. Still
GAP: 198 (ref to an element of a growing array), 230 (push of Unknown),
140 (push onto Unknown).

**Lessons:**
- A refusal in the PRODUCER is for every consumer: Deparse renders a
  loop-local `\$x` fine, and three producer tests broke. A consumer
  limitation goes on the wire as a FACT (a field) and the consumer refuses.
- A new arm in a dispatch every read goes through (`_emit_read_slot_as`)
  reaches method bodies, whose module may not declare what the arm calls:
  an `@exit` arm made 5 LLI_FAILs and 16 suite failures. Keep such arms to
  helpers the method-body needs propagation already covers.
- Never edit the producer while a check is running (the census reads it
  live): a run was stopped and redone.
