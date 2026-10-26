---
name: census-cause-arm-ends-and-c-style-step
description: 430/430 goal, "Phi node encountered before its enclosing structure" (4: 097 115 155 210) -- a C-style for's step over a `next` arm's value; on the way a SILENT WRONG ANSWER from this session: `last` after a statement in an arm was ignored; 097 round-trips (239)
metadata:
  type: project
---

**Cause:** "Phi node encountered in lower_value before its enclosing
if/loop structure was processed" (097 115 155 210).

**097's shape:** `for (my $i = 0; ...; $i += 2) { if (...) { push @o, "s";
$i--; next } ... }`. The back-edge is the STEP over the latch's merge
(`Add(Phi($i, $i - 1), 2)`); `_latch_phis` looked for the latch Phi only
as the back-edge itself, so lowering the step met it first. It now looks
through the back-edge's pure operands.

**And the arm's jump was missed:** with statements before `next`, the
latch Region's input is the arm's last statement, not its Proj, so
`_arm_loop_exit_label` never found the latch. It now follows the arm's
control chain to its end.

**SILENT WRONG ANSWER found by the shape sweep (wrong since this session,
refused at baseline):** the same miss for `last` -- `if ($x eq "b") {
push @o, "B"; last }` ran on as an ordinary arm: `a B c` for perl's `a B`.
The arm-chain walk now serves the exit check too, and the exit is never
taken for the latch (the loop heads both Regions).

**Result:** 097 round-trips; 238 -> 239 (pinned b0b982dc).

**155 (chalk 373d2620):** a loop inside a `next` arm. The arm-chain walk
now steps past a nested If/Loop to its merge; and `_process_branch_from_if`
records what a `next`/`last` arm carries BEFORE dropping the arm's cached
values -- the inner loop's phis were dropped first, and reading them
refused. 239 -> 240. Left: 115 (`last LABEL` to an outer loop), 210 (a
string eval).

**Lesson (again):** the shape sweep, not the census, finds the silent
wrongs -- five of them this session. Sweep `next` AND `last`, with and
without statements before them, every time arm control flow changes.
