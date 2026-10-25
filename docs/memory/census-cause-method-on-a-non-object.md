---
name: census-cause-method-on-a-non-object
description: 430/430 goal, part of "Call(method) X has no class_name" (7) -- a method called on undef or a plain value dies; lowered where nothing reads $@; 200 -> 203 of 431
metadata:
  type: project
---

**Cause:** "LLVM MOP: Call(method) X has no class_name" held 7 cases.
Three of them (422, 423, 425) aren't dispatch at all. `state $n`,
`field $x` and `defer {...}` with no feature turned on parse as indirect-object METHOD
CALLS on undef or a plain value, which perl dies on.

**Built (chalk c452df61):** _lower_method_on_non_object.
- A plain invocant (Int/Num/Str/Boolean/Undef, or a Print's value) always
  dies.
- A Scalar, or an untyped `my $x` location, is read by its tag at run time.
  One holding a reference (an object of a run-time class) exits 255.
- The die is a branch to its eval, lowered ONLY where the program never
  reads $@. perl's message names the file and line, and B::SoN's JSON
  carries neither (no `source`, no line on nodes), so the message is
  lowered only where it is unobservable. Outside an eval it would be
  printed: refused.
- When possibly an object and the die can't be lowered, the old
  no-class_name refusal stands. A misleading "non-object" GAP was briefly
  given to real object cases (012, 136); caught and reverted.

**Lesson: consumers are not every value use.** `$@`-read detection by
`$d->consumers` missed a Coerce that reads it (the read EntryDef listed
only its control successor, Print). Scanning every node's INPUTS found
it. Other code that relies on consumers for a soundness check
(_emit_array_slice_into's alias check, _lower_select's value-use check,
_calls_in_body) should be reviewed with this in mind.

**Result:** 200 -> 203. The remaining 4 (012, 059: `can`; 136: `add` on
`$s` in a try; 248: `->id` on a map's `$_`) are dispatch on a run-time
class: blessed/can/@ISA work.
