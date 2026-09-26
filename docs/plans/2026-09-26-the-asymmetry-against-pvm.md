# Where we stand against a working implementation

**Date:** 2026-09-26
**Status:** MEASURED. Diffed our round-trip results against pvm's ratchet over
the same 212 programs.

## The two numbers, on identical input

    pvm      204 / 212 clean    8 refusing
    B::SoN   140 / 209 round-trip

Different questions -- they assert a parse, we assert a round trip through an
IR -- so the gap is not a scoreboard. What makes the comparison worth running
is that IT IS NOT THE SAME PROGRAMS FAILING, and each direction of disagreement
is a finding for whichever side is wrong.

Their ratchet is `internal/conformance/testdata/corpus.ratchet`, one line per
case as `<refusal-code|-> <file>/<title>`, so this needed no coordination.

## THEY refuse, WE round-trip: 5 of their 8

    trailing_tokens          argument-extent   A `($)` prototype cuts the extent to one
    trailing_tokens          argument-extent   A parenless call is greedy
    trailing_tokens          named-operators   `undef` is two operators wearing one word
    tokens                   unary             The file-test operators
    unimplemented_statement  ungated           `defer` without its feature runs the block FIRST

Five programs their parser refuses and perl's optree gave us enough to
round-trip. Those are findings for them, and they said they want them.

The other three of their eight are adjacency cases, which by construction fail
while any construct in their tier does -- we refuse or differ on all three too.

## WE fail, THEY handle: 65

    41  DIFFERS    we build a graph and the emission prints the wrong thing
    22  REFUSED    we refuse
     2  NOJSON     the producer emitted nothing

Excluding 3 cases that looked like disagreements and are not: `parses: no`
fixtures, where their ratchet records `-` because a refusal code does not apply
and we record NOPARSE. Both sides agree perl rejects the program.

By topic, most-blocked first:

    3  list-operators-in-context, embedded-code, class-feature,
       bless-dispatch, arguments
    2  symbol-table, regex-pattern-positions, pod-and-data, named-operators,
       loading, jumps, handles
    1  the long tail

## What this changes

THE 65 IS THE ACTIONABLE LIST, and it is better than the 69-remaining figure it
refines: every one of these is a program a working Perl implementation handles,
so none is blocked on a question about Perl. They are all ours.

It also splits cleanly by who inherits the defect. The 41 DIFFERS are graphs
that translate and lie -- chalk gets them wrong too. The 22 REFUSED are honest.

A METHOD NOTE. My first pass reported 68 and three of them were the `parses: no`
cases, matched by a lookup that took the FIRST case in a topic rather than the
one named. Same class of error as the harness bugs earlier this session, caught
by noticing that a NOPARSE case cannot disagree when `perl -c` is the shared
oracle. See [[verify-the-harness-before-reading-its-output]].

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
