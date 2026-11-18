---
name: a-list-assign-into-an-aggregate-is-placed-or-refused
description: `my ($f, @rest) = LIST` / `my ($k, %h) = LIST` -- T2 refused all of it by one blanket check. Two causes in two layers. B::SoN places the Assign (chain + memory version) only by accident; T2 had no slurp lowering. T2 now fills a placed one; the rest is a producer change awaiting perigrin
metadata:
  type: project
---

`my ($f, @rest) = (1,2,3)`, `... = f()`, `my ($k, %h) = ("x", a => 1)` all
refused as "a list assignment to an array or hash" (Lower.pm, a blanket check
from 2026-11-11 guarding a silent wrong answer: "1 " for "1 2 3").

**The 11-11 "floating" claim still holds (2026-11-18), for a known set of
shapes.** B::SoN's aassign fallback (FromOptree.pm ~11810-11985) builds
`Assign[targets..., values...]` and then:

| RHS | wire | unguarded T2 |
|---|---|---|
| literal list, an array, a `(...)` in a branch | FLOATING: no control, no consumer; reads of `@rest` are `PadAccess` at MemStart | WRONG "1\|" |
| one call / slice / match (`$single_call`), `my` | pinned + memory version (reads take the Assign) | was refused in list_assign |
| anything, in a loop body | pinned + memory version | was refused |
| `($x, @r) = f()` declared earlier | pinned, NOT the memory version: later reads still at the memory before | would be wrong |

The pinned rows are an accident: `_is_aggregate_node` judges by STAMP, a
memory-form `my @rest` PadAccess is stamped Unknown (or Str, by a use), so the
"no aggregate target" branches take it for a scalar.

The same stamp-not-sigil test makes the positional rebind wrong, older than
this work and wrong at baseline with no array target at all:
`my @r; push @r, 2, 3; my ($f) = @r; pop @r; print $f` printed 1 -- `$f` is
bound to the `@r` node itself (`Coerce(PadAccess @r)`), `$s` in
`my ($f, $s) = @r` to undef ("2 " for "2 3"), pinned or not.

**Chalk (branch list-assign-agg):**
- `Chalk::IR::Node::Assign::is_placed` (T1): on the chain, and every reader of
  an array/hash target comes after it (forward control reach from the Assign;
  a reader's memory operand, or what the read is made into, must be in it;
  MemStart is not).
- list_assign: scalars by place, the first `my` array/hash takes the rest
  (`ArgsFrom` + `AAssign`/`HAssign` in place), targets after it get nothing;
  its count is its value in scalar context.
- Refused by name, each a wrong answer seen: not placed; a target B::SoN also
  binds as a value (`my @r = (9, 9); ($x, @r) = f()` read "9 9": the reads
  stayed the literal's); a reference taken of the target in a loop body (one
  array for every pass: "3 6 6" for "3 2 6" -- the wire does not say the `my`
  is the pass's); scalars from a memory-form array (the baseline wrong above).
- An odd list into a hash where warnings may be on stops at run time, by name
  (chalk raises none of perl's warnings; the Assign carries no file/line).

**Producer change needed (NOT made; perigrin's approval):** in the aassign
fallback, an array or hash target BY SIGIL pins the Assign and makes it the
memory version (as the demoted-target branch does), rebinding the slot to the
target PadAccess where it was bound to a literal; and the positional rebind
must treat a `@`/`%` PadAccess (target or value) as an aggregate by sigil.
Tried in a scratch copy only -- see the report of 2026-11-18.

## Lessons

- A blanket refusal hid three more wrong answers behind it (bound-as-value,
  loop reference, scalars-from-array). Probing shape variations after lifting
  it found each; the suite and the 1904 probes found none.
- "Is it on the chain?" was not the question. Pinned-but-not-the-memory-
  version reads wrong too; ask where each READER stands.
- `perl_may_warn` answers "may a `__WARN__` handler be missed", and is undef
  for a program with no handler -- not "are warnings on". Read a helper's
  body before reusing its name (`warnings_may_be_on` split out).
- A shell glob `s0?` with no `.pl` matched nothing and the loop printed four
  lines; the filtered output looked like "everything else round-trips".

Tests: chalk `t/bootstrap/ir/t2-a-list-assign-fills-its-aggregate.t`
(floating shapes assert "as perl, or refused by name", so the producer fix
turns them SAME without a test edit).

Related: [[unknown-arity-means-leave-the-bindings-alone]],
[[assign-targets-are-positional]], [[a-lifted-refusal-shows-what-it-hid]],
[[a-refusal-test-that-only-translates]].
