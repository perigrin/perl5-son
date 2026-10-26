---
name: census-cause-eval-in-a-loop-body
description: 430/430 goal, "a call in a block eval that is not lowered as a branch" (3: 171 172 173) -- the loop body now goes through process_control_node; on the way two older invalid-IR bugs (a try body value at the catch merge; a coercion opening blocks in an arm tail) and two older WRONG answers recorded (a dead may-die value)
metadata:
  type: project
---

**Cause:** "a call in a block eval that is not lowered as a branch (in an
arm or a loop body)" (171 172 173: try/catch in a foreach, with last /
next / return in the catch).

**Why:** `_process_loop_body` lowered its statements with `lower_value`;
an if arm uses `process_control_node`, which opens an eval at its entry
(`_open_evals_entered`) and closes it at its join Region. The loop body now
does the same. 171 172 173 round-trip (240 -> 243).

**Older invalid IR found on the way (both fixed):**
- `try { $c = g(2) } catch ($e) { $c = "x" }` at top level: the catch merge's
  Phi takes g's value on the no-error arm, but that value is made in the
  body and does not dominate the eval's join. close_eval now gives each
  body value a later Phi reads a join phi (undef along a die, where no path
  reads it). A body value read past the join any other way is REFUSED
  (`eval { $c = g() }; print $c` -- on a die perl keeps $c's old value, and
  the graph carries no merge of old and new). Constants are re-made; a
  `my @a` (entry-made) is exempt; values made before the first die point
  dominate and are exempt.
- `_coerce_arm` emitted a multi-block coercion (Int -> Str) in an arm's tail
  and left the arm's branch in the first block: the merge named the wrong
  predecessor and the last block had no terminator. It now moves the arm's
  terminator to the last block and returns that label.

**OLDER WRONG answers (at the session baseline), not yet fixed:**
`my $z = 0; my $q = 1 / $z; print "x\n"` and `my @a = (1, 2); my $p =
\$a[-5]; print "x\n"` print `x` where perl dies -- a dead value that may
die is dropped. They were probes outside allprobes.txt, so no sweep saw
them. Task: report (task #6) and fix.

**Test updated:** llvm-an-eval-catches-its-die.t asserted an eval in a
loop is refused; it now accepts perl's answer or a named refusal.
