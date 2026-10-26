---
name: census-cause-glob-assigned-code-ref
description: 430/430 goal, "a code reference used as a value" (4: 011 027 399 407) -- `*name = sub {...}` bound statically when certain (one write, no named sub, no captures, every call after it in the same graph); 407 round-trips
metadata:
  type: project
---

**Cause:** "a code reference used as a value -- not called where it is
made" (011 027 399 407).

**Built:** Analysis `_attach_glob_bound_subs`: an EntryWrite of an AnonSub
to `&name` makes the direct calls of `name` calls of that sub, and marks
the AnonSub `glob_bound`; the backend lowers that EntryWrite to nothing.
ONLY when certain -- the one write of `&name` in the program, no sub
declared by that name, a body with no CellParam (captures nothing), and
EVERY call of the name following the write on the same graph's control
chain. Probed as refused: a conditional write (the call after the merge
reaches a Region, not the write), a call from another sub, a write in a
loop.

**Result:** 407 round-trips. 011 next hits `missing()` (AUTOLOAD); 399 is
`&$show` (a call with the caller's @_); 027 is `$SIG{__WARN__}`.
