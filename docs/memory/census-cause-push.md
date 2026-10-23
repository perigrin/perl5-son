---
name: census-cause-push
description: 430/430 goal, cause 4 — builtin push (11 of 39 "cannot lower op=Call"): push, join over a flattened list, $" as " "; ROUNDTRIP 77 -> 81; three wrong answers (a sub's `my @p` shared across calls, push/shift in an arm not dominating the merge); 5 left are push onto a Scalar-stamped array
metadata:
  type: project
---

**Cause:** `cannot lower op=Call` (39). The refusal didn't name the
builtin, so it now does ("cannot lower op=Call builtin push"). `push`
led with 11.

**Fix (chalk b019b022):**
- `push` appends through `_emit_append_one`, the accumulator path `map`
  uses, and returns the new count.
- A Call keeps B::SoN's `memory_input`, so a push is a memory version.
- Analysis takes an element's literal only while the array is unwritten
  (its memory is MemStart).
- `"@a"` is `join($", @a)`. join now takes a flattened list, and reads `$"`
  as `" "` while nothing writes it.

**Round-tripped:** 4. ROUNDTRIP 77 -> 81. `cannot lower op=Call` now
splits by builtin: open 8, readline 3, and many with 1 or 2 cases.

**Wrong answers found on the way, each red first:**
- `my @p;` is a bare `@` PadAccess. It was one array built at the
  program's entry, so a sub called twice saw the first call's pushes. It
  is now built where its graph's lowering began (the call point when
  inlined). The lesson: "allocate at entry" means "the entry of the
  graph", not the program.
- A push in an arm onto an array built before the if lowered the array
  lazily inside the arm, and the read after the merge didn't dominate.
  Chalk already pre-lowers an element store's container before the
  branch; push, shift and pop now join it. That also fixed shift, which
  was red at baseline.

**Pre-existing, logged:** chalk backlog 4d7c2e19. `$a[2] = 3` past the
end aborts, and `$a[5] = 3` is silently dropped (prints 2, perl 6).

**What they hit next:** 5 are "push onto a Scalar", a `my @a` stamped
Scalar by the producer. The rest are spread across other causes.
