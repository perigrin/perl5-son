---
name: a-local-in-a-loop-is-restored-on-every-edge
description: "`local $g` in a loop body: the pass-end restore ran only when the loop walk itself reached unstack; a tail after a guarded next/last is finished by an arm walk. Edges restored elements only. The saved value was a stale binding"
metadata:
  type: project
---

Probe lo3 of the 2026-11-19 audit, one of three whose wire was byte-identical
to a right program's (branch `placement`):
`our $g = 1; for my $i (1..2) { local $g = $g + $i; last if $i == 2 }` left 4
in `$g` for perl's 1. Three causes, each its own wrong answer:

- **The pass-end restore was skipped.** `_walk_loop_body` calls
  `_restore_locals` where it reaches the body's `unstack`. A body whose last
  statements follow a guarded `next`/`last` is finished by `_walk_branch`,
  which stops at the unstack with a ctx of its own and none of the loop
  walk's saves. Now `_walk_loop_body` restores what is left when it returns.
- **A `next`/`last` edge restored localized ELEMENTS only**
  (`_restore_local_elems_on_edge` filtered on `{elem}`). It restores every
  save of the pass so far.
- **The saved value was the scope binding**, what this graph last stored:
  `b(); { local $g = 2 } print $g` printed what `$g` held before `b()`. The
  save is `_entry_live_value` -- a read at the current memory version when
  some sub writes the scalar.

An edge's restore and the pass end's after it are the same store;
`_restore_locals` skips a store identical to the current memory.

The pass-end restore added here is for NAMES only. A localized element keeps
the restores its own rules place (`_local_elem_scope`,
`_restore_local_elems_on_edge`): the deparser reads the block's end from
them, and a second ElemRestore closed its `{ local ... }` block before the
statements after the guard (`000 0` for `1 0`).

SoN::Deparse binds such a save -- an EntryDef at the loop's memory Phi -- as
`$savedN` at the top of the pass (`%loop_top_bind`). Anchored as a stale
read, it was assigned at the END of the pass and the local was computed from
undef: a loop-body `local` that had round-tripped stopped doing so until
this was added.

**Lessons:**

- **Trace which walker ends the construct.** A `warn` in `_restore_locals`
  printing its caller's line and `@SAVES_STACK` showed it was never called
  from the loop walk at all -- one run, instead of reading 1500 lines.
- **Probe the neighbours of a fixed probe.** lo3 led to four more wrong
  programs (a tail after `last if`, a `next`, a callee reading the local, a
  stale save), none in the audit.
- **Still wrong:** lo2 and lo16 (`local` left by `die`: the wire has no
  exceptional edge), lo14 (a package array flattened at no version).

Related: [[a-written-package-scalar-is-never-carried]],
[[the-wire-is-checked-before-it-is-loaded]].
