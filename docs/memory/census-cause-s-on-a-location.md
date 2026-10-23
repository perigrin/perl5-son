---
name: census-cause-s-on-a-location
description: 430/430 goal, cause 6 — "RegexSubst writing the location in place" (10): s/// stores its result back to the %Slot; ROUNDTRIP 81 -> 84; two wrong answers (an arm's walk dropped an s/// it reached by data first; a computed replacement was read from the empty field)
metadata:
  type: project
---

**Cause:** an s/// on a location (a `my $x` handed to a call). The
RegexSubst is the location's next memory version, but nothing stored its
result, so cause 5 refused it by name.

**Cases held:** 10.

**Fix (chalk 0a54e6c0):**
- The rewritten string is boxed into the `%Slot`.
- The read after it is frozen at the RegexSubst's version.
- A Scalar subject is read as a string by its tag.

**Round-tripped:** 3. ROUNDTRIP 81 -> 84.

**Wrong answers found on the way, each red first:**
- An if arm's body walk follows data edges too. It reached the s///
  through the read it rewrites, before reaching its control predecessor,
  so the s/// was judged not in the arm, marked visited, and dropped.
  A pinned node that isn't on the chain *yet* is now left unvisited.
  This is the third ownership bug in that walk: decide ownership from
  the control chain, never from what was merely reached.
- A computed replacement (`s/(\d)/<$1>/`) is an operand, and the
  `replacement` field is then `""`. Read from the field, it deleted the
  match. It is now refused by name.

**What they hit next:** tr/// (3) and lvalue substr (1) on a location,
and s///r and /g flags.
