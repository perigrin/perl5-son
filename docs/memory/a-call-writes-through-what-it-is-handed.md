---
name: a-call-writes-through-what-it-is-handed
description: the loop element-read pass counted a call as a store only to elements passed as arguments; `$s = $info->{n}; emit($info)` printed the call's write. A reference-reached container counts every user call
metadata:
  type: feedback
---

The loop pass's `$targets` treats a call as writing only the element
Subscripts among its arguments. A call handed `$info` writes
`$info->{n}` through the reference. The read was spelled after the
call and printed `z` for perl's `x`. This was silent: chalk's C.pm
refused for another reason, and the repro miscompiled.

Fix: when the read's container is reached by reference, every user
(non-builtin) call after the version counts as a store. That means an
element container, a scalar, a shared aggregate, or a referenced one.
A call passed the read itself is exempt, as perl's alias.

Such a read is then bound right after its last operand made in the
iteration. That is allowed when no `if` comes between that anchor and
the first such store. The read's version precedes the stores, so perl
read it before any later `if`, even when its only use is in that `if`'s
arm. This took Perl::Target::C and Schedule::Elaborate to COMPILES.

**How to apply:** "what can this call write" means whatever it can
reach, not its argument list. And a read's memory version pins where
perl evaluated it, even when the graph floats the read.
