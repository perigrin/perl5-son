---
name: compiling-is-not-running
description: "A fix that makes the emission compile has cleared the loudest check, not the real one; run it and compare the value"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T13:11:36.749Z
---

Making a broken emission COMPILE is not making it correct. A compile error is
the loudest possible failure, so clearing it feels like the fix landed -- and
the next failure mode down is silent.

Measured 2026-09-26 on a destructive tr/// over a lexical. The emission was
`("a.c" =~ tr[.][Z])`, which perl refuses. Giving it the pad slot instead made
it compile, and three assertions went green:

    renders                                        ok
    the tr subject is a variable, not a value      ok
    the emission compiles                          ok
    and it prints what perl prints                 NOT ok

`my $tr = "a.c"` had been pruned from the graph, so the program read an
undeclared variable and printed ` 1` where perl prints `aZc 1`. **A compile
error had been traded for a wrong answer**, which is the worse of the two --
nothing downstream can notice a wrong answer.

**Why:** each check is cheaper than the last one it replaces. Inspecting a
graph is cheaper than rendering; rendering is cheaper than compiling; compiling
is cheaper than running and diffing. Every step up catches a class the step
below cannot see, and stopping at the first green is stopping at whichever
check was easiest to satisfy.

**How to apply:** the acceptance assertion is always `is runs($emitted),
runs($source)`. Compile checks are a diagnostic that names a cause, never the
pass condition. And vary the SHAPE, not just the input -- three assertions on
one statement all passed while

    my $t = "a.c"; my $c = ($t =~ tr/./Z/);
    print "mid $t\n"; print "end $c\n";

printed `mid a.c` for perl's `mid aZc`, because the mutation was emitted where
its value was first READ rather than where it happened. A single-statement case
cannot see an ordering defect.

This is [[read-generated-output-not-tests]] one rung higher: reading the output
is not running it either.

Related: [[a-silent-drop-is-worse-than-a-refusal]],
[[removing-a-gap-can-create-a-miscompile]],
[[verify-the-harness-before-reading-its-output]]
