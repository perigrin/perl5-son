---
name: a-value-by-context-is-the-return-s-two-readings
description: "Branch goal-close (2026-11-23): pl13/aun17f closed by the existing two-reading Return, marked in the handler not recognised at the exit; a count of a record's inputs and an unstamped aggregate miscount; a skipped verifier passed the suite gate; the probe verdict compares the exit status"
metadata:
  type: project
---

Producer `goal-close` from 9e40d47, chalk `goal-close` from c959f983. The
goal audit's last holds and risks 10 and 11.

**pl13, aun17f (held as V7 `record`) are SAME.** A sub value that depends
on the caller's context already had a wire shape: the Return's two inputs,
[list reading, scalar reading] (`return @a`, a merged aggregate return,
`_build_single_exit`'s contract), and chalk T2 reads it (`listret`). So no
design was needed: the list assign made in the caller's context (want 0),
by position, into package scalars is marked by the aassign handler
(`%CALLER_CONTEXT_ASSIGN`, its count made before the stores) and
`_list_assign_return` turns it into [the targets read after the stores, the
count]. Both holds are gone (ratchet, chalk's wire-verify.t).

**Lessons:**

- **Mark the node where its context is known; do not recognise it later.**
  The first try recognised "an unplaced Assign of package scalars" at the
  sub's exit. `my $n = (($p, $q) = @x); $n` returns the same Assign through
  a `my` in SCALAR context, and got a list reading (a refusal turned WRONG).
- **A record's inputs are not the right side.** A copy from an array records
  the elements it copied (`by_element`), so counting the Assign's inputs said
  2 for `($a1, $b1) = @x` of three. Count the handler's `@rhs`.
- **An aggregate by its sigil, again.** `_list_count` asked the stamp: a
  file `my @x` read in a sub is Unknown there and counted as one value --
  `sub f { my $n = () = @x; $n }` gave 1 for 3 in chalk, a silent wrong at
  base. Probe the neighbours of a fix: this one came from a neighbour.
- **prove calls a skip a success.** chalk's producer-dependent tests all
  `skip_all` without B::SoN (the convention, kept); the suite gate now keeps
  each file's test count and misses unless `t/bootstrap/ir/wire-verify.t`
  ran a test (`CHALK_MUST_RUN`, t/gates-a-skipped-verifier-fails-the-chalk-suite.t).
- **The probe verdict compares the wait status.** chalk's lowered programs
  exit as perl does (die 255, `exit 3` 3), so the exact status is a stable
  check; "both failed" took a crash for a die. No probe changed verdict.

**Open (pre-existing, refused by name in T2, a V7 `record` on a program no
probe set holds):** `($a1, undef, $b1) = LIST` as a sub's value; a
scalar-context list assign of package scalars from an array returned
through a `my`.

Related: [[the-goal-audit-s-wrong-answers-closed]], [[the-loader-holds-v2-to-its-invariant]],
[[a-held-count-is-not-a-held-name]].
