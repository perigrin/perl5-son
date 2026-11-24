---
name: the-last-two-holds-dropped
description: "Branch verify-holds (2026-11-24): aun6 and aun5d fixed in B::SoN, %HELD empty in both repos; a store passed as an operand is a version spelled wrong; every arm walk on its own Proj sets $ARM_PINS; a hold's name is narrower than its class"
metadata:
  type: project
---

Producer `verify-holds` from 74c7713, chalk `verify-holds` from 890c0ff8.
The last two wire-verifier holds are fixed in the producer, and both
`%HELD` tables are empty (t/wire-verify-ratchet.t, chalk's
t/bootstrap/ir/wire-verify.t). Gates (f6b67d59, 4ba00e14): every one PASS,
held by name 0; probes WRONG 0 (SAME 1065), census ROUNDTRIP 426, deparser
round trip 430.

**aun6** (`${"main::g"} += 10` as its sub's value, read-unversioned:through-ref).
`$$r += 5` yields the location after the store, and the op-assign handler
built that read as `PostfixDeref [ref, Assign]`: the store was a plain
operand, so the read named no memory version. It is `mem => $store` now
(t/wire-a-compound-store-through-a-reference-is-read-at-its-version.t).

**aun5d** (`next unless $x; print 4 / $x` in a loop body, effect-floating).
The rest of the body after a `next`/`last` guard is walked by
`_walk_branch` on its own Proj, but with `$ARM_PINS` left at 0, so
`_step_op` pinned nothing there: a division that may fault floated above
the guard. It sets `local $ARM_PINS = 1` now, as the guarded statement's
arm a few lines below already did
(t/wire-the-rest-after-a-loop-guard-pins-what-may-fault.t).

**Lessons:**

- **A store passed as an operand is a version spelled wrong.** In wire v2 a
  read follows memory through `mem_in` only. A node that takes the store as
  an input orders nothing the verifier or a consumer can see. Any read that
  must come after a store names the store with `mem =>`.
- **A hold's name is narrower than its class.** aun6 was held as "through a
  symbolic reference". The hard-reference `$$r += 10` as a sub's value had
  the same violation, and no probe or corpus case covered it. Probe the
  neighbours of a held case before fixing it: here `$$r`, `-=`, and the value
  assigned (`my $w = ($$r += 5)`).
- **Every arm walk on its own Proj must set `$ARM_PINS`.** It is a dynamic
  variable, so an arm walk that does not set it inherits its caller's value,
  and in a loop body that is 0. `next unless`, `next if !`, `last unless`, a
  statement before the guard, and `%` all had the same float. Grep for
  `_walk_branch(` calls that pass a fresh Proj and do not set it.
- **chalk T2 still refuses `$$r += 10` as a sub's value** when `$r` is a file
  lexical ("a scalar deref where a reference T2 does not make may reach
  it"), both before and after the change. That is a refusal, not a wrong
  answer.

Related: [[the-wire-verifier-and-its-ratchet]], [[a-held-count-is-not-a-held-name]],
[[the-goal-audit-s-wrong-answers-closed]], [[a-pinned-read-changes-no-memory]]
