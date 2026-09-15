# A statement after a nested loop was silently discarded

**Date:** 2026-09-14
**Status:** FIXED. The walk now continues past the inner `leaveloop`.

## The defect

`_walk_loop_body` stops at a nested loop's `leaveloop`, so every statement
after that inner loop is absent from the graph. Measured:

    for (@a) { for (7,8) {} print "X" }
      perl  : XX
      graph : the print is simply not there

and with a write instead of a print:

    my @a=(1,2); for (@a) { for (7,8) {} $_ = $_ + 100 } print "@a"
      perl    : 101 102
      emitted : 1 2

A silent DROP -- the worst category in the refuse-or-lower contract.

## Why it surfaced now

It was MASKED by a second bug, not caused by fixing one. Before
`9aff01c`, a nested implicit foreach leaked its iterator binding (both loops
key on `'$main::_'`), and the outer loop's write-back fired against the inner
loop's element. That produced an anonymous-container element store, which the
deparse refused -- so the file never got far enough to notice the missing
statement.

With the leak fixed, the drop became reachable, and it is now a loud refusal:

    GAP: a statement after a nested loop or bare block inside a loop body is
    not yet lowered (this walk stops at the inner leaveloop, which would
    silently discard it)

The discriminator is measured: `leaveloop->next` is `unstack` when the nested
loop ENDS the body, and `nextstate` when statements follow. A bare block spells
it identically, so one check covers both.

## What it cost, stated accurately

`comp/utf.t` moved from translating to a producer GAP. It was NOT passing
before -- measured at the prior commit, it translated and then died at runtime
with "Unsupported encoding" (4217 lines expected, 2 produced). So the change
turned a wrong answer into an honest refusal, which is the right direction, but
it DID narrow what the producer accepts and that is worth stating plainly
rather than as "no corpus impact".

A 99-file sweep reported the refusal firing nowhere. That sweep was wrong --
it fires on comp/utf.t. The lesson is the usual one: a sweep that reports zero
is a claim to check, not a result to trust.

## The fix, and a wrong premise in the way of it

The refusal's own comment said resuming was blocked because "the resume point
is shared with the top-level walk". THAT WAS WRONG. There are two `leaveloop`
handlers -- one in the top-level walk, one in `_walk_loop_body` -- and they are
separate functions with separate resume points. The body walker's own comment
says so two lines above: "a leaveloop this walk reaches belongs to a NESTED
loop or bare block, not to this body -- this body's own terminator is the
`unstack`."

So the walk simply continues past it. `_restore_locals` is NOT run on the way
through: it belongs on the boundary that ends an ITERATION, which is the
`unstack`, and running it on a nested loop's leaveloop would restore the
enclosing body's locals partway through a pass.

comp/fold.t and comp/retainedlines.t are CLEAN again, and comp/utf.t advanced
past this refusal to a different one (`map body contribution of unknown
arity`).

The lesson worth keeping: a comment explaining why something cannot be done is
still a claim, and this one was contradicted by another comment in the same
handler.
