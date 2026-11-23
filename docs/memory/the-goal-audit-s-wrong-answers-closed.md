---
name: the-goal-audit-s-wrong-answers-closed
description: "Branch audit-fix (2026-11-23): the 2026-11-22 goal audit's 288 probes (55 WRONG) to WRONG 0 -- die ending a loop body, an eval's normal-exit locals, read-before-kill in T2, vivifying reads, LocalAlias a version, no pure-by-default builtin, verifier V2b/V10; what is held and open"
metadata:
  type: project
---

Producer `audit-fix` from 2d67c84, chalk `audit-fix` from 287e5da1. The
audit's 288 one-line probes are `probes/a/au*` (producer docs) and
`t/data/audit-probes/au*` (chalk). At the base: 55 WRONG.

**Fixed, by class:**

- `die` ending a loop body (risk 1): `_walk_loop_body` had no case for it
  and stepped past what it did not know; it builds the Unwind, and refuses
  an op with no case. T2 lowers a loop no way goes round (no latch).
- An eval that ends normally puts its `local`s back (risk 2):
  `_walk_branch` restores at its stop when that is a `leavetry`/`poptry`.
- T2 makes every read at a node's `mem_in` before that node (risk 4), but
  not inside an eval's body (a read made there and used past its end is
  refused); `list_assign` keeps a memory target's pre-store read.
- A read through an element vivifies it (W9): perl marks rvalue chains'
  intermediates OPf_MOD|DEREF too; `_deref_chain_writes` deleted.
- LocalAlias is a memory version; T2 takes `$_` for an alias whenever it
  is aliased and written, read or not (a callee's `$_ = 9`).
- EffectTable: every op-map Call has a row; unknown is "writes" and the
  walk refuses it; `log`/`sqrt` fault and are pinned (T2 refuses them).
- SoN::Verify: V2 write-no-version, V2b effect-floating, V10 exc, record
  and `my`-in-memory by the target's own `mem_in`. 11 of the 12 hand-broken
  wires rejected on fresh wires; M5 is another program, not a broken wire.
- DynaLoader hold traced: compiled before peep is off; `aelemfast` refused.

**Refused by name, not fixed:** W8 (any bless beside a non-empty DESTROY
or AUTOLOAD), W10 (a shared `my` aggregate flattened beside a sub call),
`$_` read after a callee writes it, `map { die }` ("a phi stamped List").

**Held by name (ratchet and chalk's wire-verify.t):** pl13 and aun17f (a
list assign that is its sub's value: a design), aun6 (a symbolic-ref
compound assign reads at no version), aun5d (a division after `next
unless` floats: the rest of the body is an arm, unpinned).

**Open:** the audit's risks 8 (external-state ordering), 9 (an INTERNAL
ERROR on `-e` then `mkdir`), 10 (`wire-verify.t` skips without the
producer), 11 (the probe gate compares stdout only); the `dowarn`-keyed
skip of the loader's checks; the placement test's one spelling.

Related: [[a-verifier-that-reads-a-derived-flag-checks-itself]],
[[a-read-that-names-a-version-is-half-a-rule]], [[a-refusal-keyed-on-a-constant-fixes-a-probe]].
