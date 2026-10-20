---
name: a-refusal-test-that-only-translates
description: Asserting a GAP appears cannot distinguish a necessary refusal from a habitual one; run the alternative
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T16:33:40.962Z
---

A test that asserts `like $err, qr/GAP:/` proves the refusal FIRES. It does not
prove the refusal is NEEDED. To know that, you have to remove it and run what
comes out.

Measured 2026-09-26. Two files asserted the map-body-arity refusal was
load-bearing, with a careful argument:

    # appending one node that STANDS FOR N makes a consumer counting inputs
    # read 1 -- the miscompile the allow-list exists to prevent

Both helpers only TRANSLATED. Removing the refusal, the emission was

    my @phi4_next = (@phi4, reverse((5,6)[$i], (5,6)[$i]));
    print scalar(@phi4);

-- the count is `scalar(@phi4)`, a RUNTIME count of the accumulated array, not
an input count. perl flattens, exactly as it does in the source. The
input-counting consumer was hypothetical.

The same callsite then lowered correctly for BOTH `sub g {42}` (1 value) and
`sub g { ($_[0],$_[0]) }` (2 values), which is the proof that nothing needed
the arity.

THREE FILES, SEVEN ASSERTIONS, all of the same shape and all wrong -- a hash
body, a hash slice, `reverse`/`sort`, a mixed hash-plus-scalar body, and two
user subs. Every one round-trips. Two of the comments even named the escape
hatch and did not take it:

    # that is a lowering waiting to happen, not an impossibility
    # Either it refuses, or it appends the right NUMBER of contributions.
    # What it must never do is append one value standing for N.

One value standing for N is exactly right when the emission is a list and perl
does the flattening. An INPUT COUNT cannot see that -- it reads 1 whether the 1
flattens or not -- so the only assertion that distinguishes them is running the
program.

**Why:** a refusal's rationale is written by whoever could not see the lowering,
and it names a consumer that would break. That consumer may not exist. Nothing
in a translate-only test can tell the difference, so the refusal is preserved by
the test rather than by the requirement --
[[a-t2-difficulty-is-not-a-t1-refusal]] kept alive by its own guard.

**How to apply:** a refusal test needs BOTH halves.
1. It fires, and names its cause ([[a-refusal-test-must-name-its-cause]]).
2. The refusal is necessary -- which means either a measurement showing the
   alternative is wrong (run it, diff against perl), or a named consumer that
   demonstrably cannot express the shape.

Without (2) the test is asserting a habit. And when the refusal turns out to be
unnecessary, the test becomes the thing that must change: replace
`like $err, qr/GAP:/` with `is run($emitted), run($source)`, which is the fact
the refusal was standing in for.

Related: [[compiling-is-not-running]],
[[a-shape-assertion-outlives-the-shape]],
[[clean-counts-cannot-measure-progress]]
