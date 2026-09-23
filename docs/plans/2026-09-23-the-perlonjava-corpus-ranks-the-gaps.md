# The PerlOnJava corpus ranks the GAPs

**Date:** 2026-09-23
**Status:** MEASURED. No code changed. This is the ranking instrument that
t/base + t/comp + t/cmd could not provide.

## Why this corpus

`~/dev/PerlOnJava/src/test/resources/unit` holds 986 `.t` files, named by
construct, one construct per file, all runnable under real perl 5.42.0.
Our previous corpus was 39 files that happened to live in perl's t/base,
t/comp and t/cmd -- a composition nobody chose.

[[clean-counts-cannot-measure-progress]] says a GAP count is a first-failure
report and cannot measure progress. That is still true. What 986 files buy is
not a better score but a FREQUENCY DISTRIBUTION: which refusals are common
and which are curiosities.

## The producer result

    986 files    857 CLEAN    129 REFUSED    86.9% clean

This measures T1 only (optree -> IR). The deparser is a separate number.

## A measurement error worth recording

The first run of this census reported 986/986 CLEAN. It was wrong.

    ls *.t | while read f; do perl ... "$f"; done

The inner `perl` inherits the loop's stdin and consumes the file list, so the
loop runs once and reports on a fraction of the corpus. `control_flow.t` has
SEVEN GAPs and was recorded CLEAN.

Caught by asking whether the corpus even contains constructs we refuse --
grep said 9 files have `next if`, 25 have a sort comparator, 15 have a glob
assign. A 100% clean rate against that is not credible.

Fix: `perl ... "$f" </dev/null`.

[[a-sweeps-absence-is-not-evidence]] is the same lesson; add that a sweep's
PRESENCE is not evidence either when the number is too good.

## The ranking (129 refusals, collapsed by cause)

Parameterised variants are merged -- glob-to-glob alias appeared 8 times
under 8 different symbol names, which distorts a raw message count.

    11  map/grep contribution arity
     8  goto
     8  glob-to-glob alias (*X = *Y)
     8  foreach bounds shape
     7  undef(EXPR) on glob/aggregate
     7  ternary list arm
     7  s///ge
     7  multiconcat stacked dest
     7  loop control in loop body (last)
     5  slice
     5  nested loop in loop body
     4  runtime range bound
     4  nested and/or in loop body
     4  glob assign (*X = EXPR)
     4  anon sub never named
     3  unstamped back-edge
     3  ternary w/ guarded element store
     3  runtime sort comparator
     3  non-static sub operand
     3  chomp/chop on non-slot
     2  runtime regex pattern, loop control (redo), loop control in branch
        arm, format not installed, capture in s///e
     1  eight singletons

CAVEAT: this is the FIRST GAP per file. Sampled 40 of the 129 refusing files;
4 had more than one GAP, so the distribution is close but undercounts the
tail slightly.

## What this changes

`cmd/for.t`'s unstamped back-edge, which was the next candidate before this
measurement, ranks 16th at 3 files. The top of the list is elsewhere.

Three of the top items are already-known FACTS rather than artifacts --
`goto` (perl defers it), glob-to-glob alias (aliases every slot at once) and
undef(EXPR) on a glob. Those are correctly refused and should not be "fixed";
their count measures how often perl programs do something our IR deliberately
declines to model.

The rest are artifacts and are ranked by how much of a real corpus they
block.

## The demo

`examples/demo.pl` (217 lines, described upstream as a showcase of Perl):
ZERO producer GAPs. 18 methods, 505 nodes, 31 distinct ops.

The round trip refuses only because it calls `Test::More::is`, which is
external to the graph -- not a construct defect.

## Still running

The full 986-file ROUND TRIP (producer + deparser + diff against perl) is a
separate and much slower census. Not yet reported.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
