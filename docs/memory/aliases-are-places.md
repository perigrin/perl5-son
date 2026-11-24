---
name: aliases-are-places
description: "Branch alias-places: an alias not proved private is a place on the wire (fields.place); the foreach iterator in memory IS its element; V12/L10; design 3 (an assignment or ?: as an lvalue). final audit's C E G H D wrong answers: 60 of 66 SAME, 6 refused by name; the fast path's proof fails for 2.9% of call bindings on chalk's lib"
metadata:
  type: project
---

Branch `alias-places` (2026-11-24; baseline section 25; design
docs/plans/2026-11-24-aliases-as-places.md, approved with its wire change).
Rebased on clause3; producer e30a00f..e899786, chalk ..f1d9aa74. All gates PASS (census 426, corpus 222, deparse 430, held 0).

**What changed.** `fields.place` marks an access node that is storage, not a
read. B::SoN passes a sub's argument, a method's invocant, and an alias
list's item as a place unless it proves the alias private (`arg_stored_by_call`,
`stores_invocant`, `call_stores_through_args`; an unknown call proves
nothing). Chalk lowers a place to a pointer: the runtime's alias `@_`, which
already existed for callees writing `$_[N]`. A foreach iterator kept in
memory IS its element while its body is walked (the node factory builds its
slot as `Subscript [list, i]`), so the pass-end write-back,
`%AFTER_CALL_PASSING` and class G's GAP are deleted. V12 (`alias-not-private`)
checks the call half; L10 the structural half.

The final audit's wrong answers by class (its own lists, `f/<name>` = chalk `fa<name>`):

| class | n | now |
|---|---|---|
| C | 19 | 19 SAME |
| E | 18 | 14 SAME; 4 slices refused by name (j18 j25 j27 j28: a slice is no place on the wire) |
| G | 13 | 12 SAME; n10 (`values %h`) refused by name |
| H | 2 | 2 SAME |
| D | 14 | 13 SAME; i03 (a ?: of package scalars needs a real If) refused by name |

Neighbours refused before by these classes' GAPs: faj03 al1 al2 faa67 SAME;
fap03/fap11 (T2: a store through an element not made a hash first), fap07
(its sub refused), faj20/lw25 (T2), ree30/req12 (`_foreach_body_writes_its_scalar`)
refused by name. Probes: 2351 (46 new `al<name>`), SAME 1859 REFUSED 477
LOUD 15 WRONG 0; no older verdict but REFUSED -> SAME.

**Lessons:**

- **The shortcut was a silent wrong answer.** "An unknown call is not
  counted" (the last audit's named shortcut) let al/c08 print 1 for perl's 9.
  A fast path that rests on a proof must count what it cannot see as unproved.
- **A place is a second node, and node identity was a fact someone used.**
  `print $x, g($x)` re-read `$x` after `g` only because the deparser saw the
  call's input as the operand's node. With a place they differ; the optree
  rule (`$stores`) now counts the call itself.
- **Build what you place where it is iterated.** The foreach list is rebuilt
  after the walk resolves `my` items; a list placed before that rebuild was a
  version nothing iterated, and V6 lost the alias-list exemption. Place the
  node the loop uses.
- **A control node's control input is no value use** (V6): a list made where
  it stands is the Loop's entry.
- **The targeted probes were not the regressions.** Making every argument a
  place also made the code value of an indirect call (`$f->($_)`) a place: 3
  SAME -> LOUD found only by the full probe set (ca20, fak23, fak24).
- **Under load, `timeout 10` fails tests.** The deparse round trips run each
  emitted program under a 10 s timeout; at load 12 forty files "failed" with
  empty output and passed alone. Rerun a failure alone before believing it.
- **A new version kind needs `SoN::Wire::as_v1` told.** The deparser reads
  v2 through as_v1, which guesses which `mem_in` was a v1 operand by kind. A
  placed alias list (one that vivifies) was taken for a read of memory, and
  MemStart reached the deparser as a value: two producer tests over Carp's
  `for ($::{$p})`, found only by the full suite (gates1).
- **A fast path the producer proves is checked against a verifier that may
  be wrong too.** V12 first flagged a `local` (another variable) and rightly
  flagged a foreach over @_ the producer had called private -- read both
  before fixing either.
- **Reading through a new path exposes an old type.** The iterator read as
  its element met chalk Analysis typing `my @c = @$r`'s element as an Array
  (fixed: a deref in a literal flattens).
- **`-MO=...` runs in `-c` mode: END blocks are skipped.** Print a
  measurement where B::SoN writes the wire, not in END.
- **Never edit what a running sweep reads** (again): a ModSets edit landed
  in a live probe run; the run was stopped by PID and redone from a copy
  (`snapprobe`).

Open: a slice as a place (a further wire shape); a `?:` target whose arms need a
real If (package scalars, elements, nested); a string op= of an assignment;
the iterator over a call's list (`values`).

Related: [[the-final-audit-s-wrong-answers-lowered-or-refused]],
[[a-foreach-alias-write-is-a-store-where-it-stands]],
[[a-background-run-reads-a-snapshot]], [[the-foreach-alias-is-a-reference]].
