---
name: truncated-output-manufactures-facts
description: head -1 on a multi-line error invents a distinction that is not there
metadata:
  type: feedback
---

A peer session reported "perl gives an ARITY error, not a syntax error" for
`sub ni ($&) { } ni { 1 } (2)`. It gives BOTH. The claim came from piping to
`head -1`, seeing one message, and reading the absence of the second as a fact
about perl.

**Why:** every `| head -n`, `| grep -o`, `2>&1 | head` in a probe is a filter
that can remove the evidence that would have falsified the conclusion. The
output looks complete because something was printed. This is the measurement
analogue of [[a-sweeps-absence-is-not-evidence]] -- there, absence from a
listing; here, absence from a truncated stream.

**How to apply:** when a probe's conclusion is about what is or is not present
in output -- "no error", "only this error", "nothing was emitted" -- re-run it
unfiltered before claiming it. Truncate for READING volume, never for deciding
a negative. And prefer asserting the positive property: the peer's test now
asserts "`($&)` does not license the block form" rather than "the error is
arity, not syntax", because message text and ordering are not promised by perl
and a test pinned to them fails a future perl for no semantic reason.

Same session, same shape, three times: `env VAR=1 perl ...` silently producing
no output, a `ps` filter that missed two 28-hour processes, and this. All three
were filters mistaken for measurements.
