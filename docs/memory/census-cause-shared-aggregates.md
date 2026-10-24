---
name: census-cause-shared-aggregates
description: 430/430 goal, cause "a store to a shared file lexical @p/%h that is not a scalar" (~17 across names) — one aggregate behind a module global pointer; whole-aggregate reads frozen at their memory version (a wrong answer found by probe); plus a B::SoN fix typing package-method calls; ROUNDTRIP 142 -> 149 of 431
metadata:
  type: project
---

**Cause:** "a store to a shared file lexical @p (or %h, @seen, %cache,
...) that is not a scalar" held about 17 cases across the different
variable names at 80cfbcbe. The census ranks causes by their text, so
this group only looked big once the names were added together.

**Built:**
- A shared `@x`/`%x` (file-level, or a sub's own captured by a
  closure) lives behind `@lexa_x` / `@lexh_x`, a module global pointer.
- `@chalk_lex_array` / `@chalk_lex_hash` make it empty the first time
  any graph reaches it.
- A whole assignment copies the new header over the old one in place,
  so a reference taken earlier still names the same aggregate.
- The globals and helpers are emitted in the post-class re-emit, after
  every body has named its own (absorbed like `_lex_globals`).

**Wrong answer found by probe:** `my $a = "@p"; @p = (); ... "$a"` read
the `()`. Reads of a whole aggregate (`Count`, and
`join`/`sort`/`reverse`/`keys`/`values` with a memory input) weren't
frozen at their memory version the way Subscript reads are. With a
plain local array the read came out right anyway; behind one shared
cell, a read lowered at its use sees later stores. `_freeze_memory_reads`
covers them now.

**Producer fix along the way (B::SoN 1fa…, `_callee_return_type`):** a
method call on a package is typed by the package's sub of that name.
chalk doesn't re-derive a node the producer stamped Unknown, so the
typing has to happen there. A chalk-side attempt didn't help and was
dropped.

**Round-tripped:** 142 -> 149. 066, 108, 131, 132, 142, 148 and 183
work now.

**What the rest hit:** push of a Scalar, a list in `@_`, `reverse`,
sort with a string comparator, and List/Array elements in a literal.
