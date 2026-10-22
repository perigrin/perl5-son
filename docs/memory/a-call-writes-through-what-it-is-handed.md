---
name: a-call-writes-through-what-it-is-handed
description: the loop element-read pass counted a call as a store only to elements passed as arguments; `$s = $info->{n}; emit($info)` printed the call's write. A call handed the container now counts; "any call through any reference" refused a dozen modules
metadata:
  type: feedback
---

The loop pass's `$targets` treats a call as writing only the element
Subscripts among its arguments. A call handed `$info` (or `\@a`, or
`@a` flattened) writes `$info->{n}` through it. The read was spelled
after the call and printed the call's value. This was a silent
miscompile: `zz` for perl's `bc`.

Fix:
- A user call handed the read's container itself counts as a store.
  The walk goes through pure nodes but stops at Subscript and
  PostfixDeref, whose values are elements.
- A foreach or grep element read by its counter is exempt (perl's
  alias).
- The read is bound right after its last operand made in the
  iteration, when no `if` comes before the first store. Its version
  precedes the stores, so perl read it before any later `if`, even
  when its only use is in that `if`'s arm.
- With nothing made in the iteration, over a named lexical aggregate,
  it is bound at the top of the body. An element read neither dies nor
  autovivifies.
- When no anchor fits and only container-handed calls are in play, the
  read is left as it was before (a logged risk).

The first version counted ANY user call for any container reached by
reference. That refused 12 chalk modules (`$self->{x}` beside
`$self->method`). The usual write is to the referent, not the slot.

**How to apply:** "what can this call write" means whatever it is
handed. Widening it to "whatever it could reach" is right in theory
but refuses most method-heavy code. Measure the census before calling
a broadening done.
