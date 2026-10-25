---
name: census-cause-runtime-dispatch
description: 430/430 goal, "Call(method) X has no class_name" (6) -- dispatch by the bless table over the packages declaring the sub; producer memory flag taken wholesale miscompiled 124; 220 -> 222
metadata:
  type: project
---

**Cause:** "LLVM MOP: Call(method) X has no class_name" (012 059 087 136
202 248), a method on an object whose class is known only at run time.

**Built (chalk 7f3db4c3): _lower_runtime_dispatch.**
- The candidates are every MOP class with a SUB of that name. The
  invocant is a ref (HashRef/ArrayRef/ScalarRef), a Scalar by its tag, or
  an element stamped Object, read as its Slot. Through an inlined
  argument it follows _arg_bind to the caller's element first, because
  the callee's `$_[0]` has no array.
- @chalk_bless_get gives the class; each candidate is a memcmp arm
  inlining that sub via `_call_via`, with an arm-local cache. The arms
  meet in a %Slot phi, coerced to the call's stamp (Analysis may type it
  from a candidate's return).
- Refused by name: inheritance or AUTOLOAD anywhere, a `class` method of
  the same name, a candidate returning a list, and any class the program
  blesses into (constant bless classes; with a run-time bless, the
  `->new` class_names) that lacks the method. Without that last check,
  probe dp3 exited 255 where perl dies naming the file and line: a
  probe neither perl's output nor refused by name.
- Found on the way: `cmp`/`eq` over a Scalar (stringify by tag); length
  of a Scalar (undef exits 255); a memory Phi over a METHOD call.

**Lesson -- don't trust a broad flag to replace a structural check.**
Making _is_memory_phi return true for any Phi B::SoN flags `memory` let
pvm 124's cycling arm walk lower, and it printed nothing (DIFFERS 1). A
narrow rule (a method call is a memory version, like a direct call) gave
dispatch what it needed.

**Result:** 220 -> 222 (087 202). Next: 136 (a call in a try body, not
lowered as a branch), 012/059 (`can`), 248 (feature-class objects).
