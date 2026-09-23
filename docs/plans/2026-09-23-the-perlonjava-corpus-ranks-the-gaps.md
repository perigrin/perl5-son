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

## The round trip (983 of 986)

    ROUND-TRIPS    6
    DIFFERS       38
    refused      939

That headline is nearly meaningless on its own, because ONE structural fact
dominates it. Split by cause:

    611  a call to a sub not in the graph   -- Test::More and friends
    213  no main::__PROGRAM__ emitted
      1  NO GRAPH
    114  a construct GAP (the real number)

891 of the 986 files `use Test::More`. The deparser refuses to emit a call to
a sub outside the graph, because the emitted program would die calling it --
correct, and exactly what examples/demo.pl hit despite translating with zero
producer GAPs. That refusal measures the corpus's dependency on an external
test module, not our coverage of Perl.

Sampled 60 of the 213 `no main::__PROGRAM__` files: 24 fail to COMPILE at all
(`Can't locate B/Flags.pm`, etc -- missing CPAN modules, never our defect) and
36 compile and hit a producer GAP. The GAPs they hit are the same kinds
already ranked above -- map arity, s///ge, foreach bounds -- so this category
adds no new vocabulary, only volume.

THREE FILES DID NOT COMPLETE: code_too_large.t (484K of generated source),
makemaker_stale_blib_source.t and map_source_mutation_snapshot.t hung and were
killed. 983 of 986 is the denominator above.

### What the round trip is good for here, and what it is not

This corpus was built to test a Perl IMPLEMENTATION by running it. Every file
is a TAP script that loads a test framework. Our round trip needs a program
whose whole call graph is present, so a corpus of framework-using test scripts
is close to a worst case for it.

The PRODUCER number (857/986 clean) is the one this corpus measures well. For
the deparser, t/*.t round trips and the 39-file perl corpus remain the
instrument, and a deparser census over this corpus would need either the test
framework inlined or the external-call refusal relaxed -- neither of which is
worth doing to move a number.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
