# Auditing the 13 GAP kinds: fact, or phase artifact?

Item 2 of docs/plans/2026-09-17-the-gap-shape-is-inverted.md. The criterion is
the one the glob work established:

    A FACT        the answer is absent from the program. perl itself defers it,
                  or no static count/type exists. Refusing is correct.
    AN ARTIFACT   the answer is present and the walker cannot reach it -- wrong
                  phase, unbuilt lowering, or a shape the walker does not model.

Every classification below is a MINIMAL REPRODUCTION, not a reading of the
message. Two of them contradict the message's own wording, which is why.

## Census (t/base, t/comp, t/cmd -- 17 GAPs, 13 kinds)

    3  a bare block with a `continue` block          ARTIFACT
    2  map body contribution of unknown arity        BOTH -- see below
    2  assigning to a glob (*FH = shift)             FACT
    1  `write` whose format is not installed         FACT
    1  void-context 'or' arm did not converge        ARTIFACT
    1  void-context 'and' arm did not converge       ARTIFACT
    1  untranslatable op in if/else arm (`return`)   ARTIFACT
    1  untranslatable op in if/else arm (`range`)    ARTIFACT
    1  undef(EXPR) on a glob (rv2gv)                 FACT
    1  loop-carried value loses its stamp            ARTIFACT (see 1c2e543)
    1  function exit inside a loop body              ARTIFACT
    1  element store in a nested one-armed branch    ARTIFACT
    1  a loop inside a branch arm                    ARTIFACT (shape unknown)

## THE PLAN'S HYPOTHESIS WAS HALF RIGHT

It predicted "the convergence ones read like artifacts; the arity ones read
like facts." The first half holds. The second is wrong, and interestingly so.

### until is an artifact, and `while` proves it

    my $i = 0; $i++ while $i < 3;    translates
    my $i = 0; $i++ until $i >= 3;   GAP: until (or-condition) loop

The same loop with an inverted condition. Nothing about the program is less
knowable; the lowering is simply unbuilt. The convergence refusal itself is
CORRECT where it fires -- its comment says it refuses rather than "emit a
straight-line merge that silently computes one iteration," which is the right
call. What is an artifact is that `until` reaches it at all.

### map arity is TWO CASES refused as one

This is the inverted shape again, and the sharper example than the glob was.

    sub gen { return (1,2) }                        FIXED arity
    sub gen { return $n > 1 ? (1,2) : (9) }         DATA-DEPENDENT

Measured, the fixed-arity callee's graph carries the count:

    main::gen
      3 ArrayLiteral List [1, 2]
      5 Return [3, 4]

and its sub record says `return_type: List`. So the TYPE is known and the
COUNT is known, for this callee -- but the refusal reads only the type, and
`List` cannot say 2. The data-dependent case has no static count at all and is
a genuine FACT.

One refusal covers both. The fixed case is an artifact of asking the stamp
instead of the Return.

## WHAT SHOULD GAP, RESTATED

perigrin's position: the only thing that should GAP is eval of a string read
from outside the system. The audit says the corpus is nearly there --

    genuine facts   4 of 17   glob-from-a-Call, undef(*GLOB), `write` format,
                              and the data-dependent half of map arity
    artifacts      13 of 17

and none of the four is string eval, which still does not GAP (it becomes
`Coerce(Scalar -> Code)` -- see the parent plan).

## Remaining work

1. Split the map-arity refusal. A Call whose callee's Return carries a literal
   list has a known contribution; only a data-dependent one refuses. Same
   shape as the glob fix: read the graph, not the stamp.
2. `until` is a missing lowering, not a fact. It is the cheapest artifact here
   -- `while` already works.
3. The `continue`-block and function-exit-in-loop kinds are control flow the
   walker does not model. Real work, correctly refused today.
4. `a loop inside a branch arm` did not reproduce from the obvious shape
   (`if ($c) { for my $i (1..3) {...} }` translates). Its trigger in comp/utf.t
   is unidentified; the message says "its leaveloop arrived without its
   operands." Needs its own reduction before it can be classified.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
