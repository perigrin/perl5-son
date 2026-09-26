# Step 3 scope: what "build IR for the corpus" actually means

**Date:** 2026-09-26
**Status:** SCOPE, ready for a crochet milestone. Measured, not projected.

## The corrected baseline

pvm's corpus, 212 cases, measured with `not_package=SoN` so every package in a
fixture reaches the graph:

    PRODUCER    198 CLEAN     11 GAP      3 NOPARSE
    ROUND TRIP  134 correct   42 DIFFERS  31 REFUSED   2 NOJSON   3 NOPARSE

The output blocks were verified against real perl first -- 209 match, 0 differ
-- so a diff against a block is a diff against perl.

## The framing was wrong

"Build IR for the corpus" implies the IR is missing. It mostly is not: 198 of
209 parseable cases produce a graph. What is missing is CORRECTNESS in graphs
that already translate.

    209 parseable
    198 produce a graph          <- what a GAP census measures
    134 confirmed correct        <- what the round trip measures
     42 produce a WRONG answer   <- invisible to any GAP count

Every one of the 42 reported CLEAN in the producer census. That is the
argument for the round trip being the gate:
[[read-generated-output-not-tests]] automated.

## The work, in three buckets

### Bucket 1: silent miscompiles (42 cases, ~24 causes)

Graphs that translate and are wrong. CHALK INHERITS ALL OF THESE -- none is a
deparser rendering artifact; the graphs themselves are wrong.

Detailed per-case diagnoses are in
docs/plans/2026-09-26-the-round-trip-over-pvms-corpus.md. Clusters worth
sizing here:

    4  a TEXT SECTION AFTER THE PROGRAM is dropped   __DATA__, formats
    3  shadowed my/state collapse                    two pad slots become one
    3  `use` neither loads nor imports
    3  regex-embedded code never runs                (?{ }), qr// with a block
    2  a deref wraps the reference                   @{$r}, %{$r}
    8  an lvalue-requiring op gets an inlined value  lock, pos, tied, tr///
    ~  the rest: //= vanishing, @_ aliasing, substr lvalue, magic string
       increment, index 3-arg transposed, list-vs-scalar context (localtime,
       split, <$fh>), caller arity, prototype, die's list extent, \*STDOUT

THE FIRST CLUSTER IS NOT A HANDLER BUG. `__DATA__` and a format body are not
optree ops, so a walker that only reads the optree cannot see them. The
producer needs a mechanism it does not have -- read them from the FILE. All
four currently emit NOTHING, a silent drop.

THE LVALUE CLUSTER IS ONE CAUSE, EIGHT CASES. `lock(($ENV{N} // 7))` --
inlining a value where perl requires a modifiable operand. Cheapest big win.

### Bucket 2: honest producer GAPs (11 cases, 8 causes)

    3  runtime range with a non-constant bound (1..$n)
    2  delete slice
    1  range inside a loop body
    1  redo inside a loop body
    1  last inside a loop body already has a loop condition
    1  do BLOCK while COND
    1  multiconcat stacked destination
    1  goto

### Bucket 3: the goto family

Scoped separately in docs/plans/2026-09-25-goto-is-polymorphic-over-its-
operand.md. T1 resolves the operand's type and emits distinct node kinds; four
of five forms are lowerable.

## Ordering

Bucket 1 before bucket 2. A GAP is an honest refusal; a wrong graph is a
silent miscompile, which [[a-silent-drop-is-worse-than-a-refusal]] ranks
worse. Fixing GAPs first would grow the corpus of graphs that translate while
leaving the ones that lie.

Within bucket 1, by cases-per-cause: the lvalue cluster (8), then the text
section (4), then shadowing (3), `use` (3), regex code (3).

## What must come with it

A ROUND-TRIP GATE IN OUR SUITE, not a one-off census. The producer census
called all 42 of these CLEAN, so a GAP count cannot defend this work. The gate
needs the corpus copied in, the extractor, a runner, and the duplicate-title
guard pvm warned about -- case titles are prose and nothing structural stops a
collision, which silently drops a case in any consumer keying on them.

## Caveats

  - `NOJSON` (2 cases) is undiagnosed: the producer emitted no JSON at all.
  - The 31 REFUSED under round trip exceed the 11 producer GAPs, so ~20 are
    DEPARSER refusals. Not separated, and they are ours alone rather than
    chalk's.
  - Cause counts are per-case-sampled, not exhaustive: two cases sharing a
    message may have different roots.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
