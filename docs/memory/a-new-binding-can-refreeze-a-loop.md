---
name: a-new-binding-can-refreeze-a-loop
description: "Binding a value to a temporary is a hoist; inside a loop that re-reads its condition it never terminates, and a hang hides as a slow suite"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-27T00:36:06.258Z
---

Binding a node to a temporary IS A HOIST, whatever the reason for it. If a loop
re-reads that value every pass, one temporary freezes the condition and the
emitted program spins forever.

Measured 2026-09-26 adding a "stale package read needs a temporary" pass to the
deparser. It bound the condition operand of a C-style `for`:

    $stale10 = $main::i;
    while (($stale10 <= 3)) { ... $main::i = ($stale10 + 1); }

`t/wire-c-style-for-over-a-package-scalar.t` already documented this exact
failure in its own comment -- "a `while` or C-style `for` RE-READS its condition
every pass, and the same hoist never terminates" -- and `_loop_invariant_roots`
already gates on `Loop.bound eq 'entry'` for it. I added a second hoist with no
gate, from the other side of the file.

**How it presented, which is the dangerous part:** not as a failing test. The
suite ran 47 minutes with no output and looked slow. `wc -l` on the task file
said 12 lines for an hour. What was actually happening:

    144440  334781 99.0  perl /tmp/oracle.144248.pl        <- 93 HOURS, another session
    2121834   6073 92.7  perl /tmp/gQrACxF1Zs/r.*.pl       <- the frozen loop

Two wrong diagnoses on the way: I read the zsh WRAPPER's elapsed time and
concluded the parents were idle, then `ps --ppid` on those wrapper PIDs found no
children and I called it hung. The work was real and running the whole time,
under different PIDs.

**Why:** a hoist is defined by WHERE the binding lands, not by why it was
created. Every mechanism that assigns a value to a variable and rewrites later
reads to name it is the same transformation, so it inherits the same
termination constraint -- and the constraint lives in whichever mechanism was
written first.

**How to apply:** before adding any pass that binds a node to a temporary, ask
what re-reads it. If a Loop's condition or body consumes it, leave it alone. And
grep for an existing hoist first: a gate already written (`Loop.bound`,
`_loop_invariant_roots`) is the specification, not just prior art.

For diagnosis: `ps -eo pid,etimes,pcpu,args --sort=-pcpu | grep perl` reads the
real processes. A suite with no output is not necessarily slow -- look for a
child at 95% CPU with a `/tmp/*/r.*.pl` name, and check for orphans from earlier
sessions while you are there.

Related: [[compiling-is-not-running]],
[[removing-a-gap-can-create-a-miscompile]],
[[one-operator-five-declaration-sites]],
[[a-sweeps-absence-is-not-evidence]]
