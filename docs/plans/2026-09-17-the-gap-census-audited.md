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
    2  map body contribution of unknown arity        FACT (both are &{$sub})
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
    -  a loop inside a branch arm                    FIXED (see 4)

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

### map arity: I CALLED THIS AN ARTIFACT AND IT IS A FACT IN THIS CORPUS

Corrected after reading the refusal site and the two files that reach it. The
first version of this audit said the refusal "reads the stamp" and could be
split. Both halves were wrong.

IT DOES NOT READ THE STAMP. It keys on node kind plus an explicit, measured
list of scalar builtins, and its own comment already states the finding I
thought I was making:

    "a user sub's arity is a property of the CALLEE that the graph does not
     carry -- measured, `sub g {42}` yields 1 and `sub g { ($_[0],$_[0]) }`
     yields 2 from an identical callsite"

AND BOTH CORPUS OCCURRENCES ARE UNNAMEABLE. comp/proto.t:351 and :368 are

    print map { &{$sub}($_) } @{$array}

a coderef call through a variable. There is no compile-time name, so no
post-pass lookup can reach a callee -- this is `*FH = shift` again, and it is
a FACT.

A NAMED fixed-arity callee IS an artifact -- `sub gen { return (1,2) }` puts
`Return [ArrayLiteral[1,2], ...]` in the graph, and `map { gen($_) }` still
refuses. But no corpus file exercises it: the two files with a named call in a
map body (comp/retainedlines.t, comp/utf.t) do not GAP here. Fixing it would
be building for a case nothing measures.

The phase story is the same as the glob's -- FromOptree walks ONE CV and has
no access to a callee's graph -- but the payoff is not, because the corpus
cases have no callee to find.

## WHAT SHOULD GAP, RESTATED

perigrin's position: the only thing that should GAP is eval of a string read
from outside the system. The audit says the corpus is nearly there --

    genuine facts   5 of 16   glob-from-a-Call (x2), undef(*GLOB),
                              `write` format, map-arity via &{$sub} (x2)
    artifacts      11 of 16
    unclassified    0 of 16

and none of the four is string eval, which still does not GAP (it becomes
`Coerce(Scalar -> Code)` -- see the parent plan).

## Remaining work

1. WITHDRAWN. Both corpus occurrences call through a coderef variable, which
   has no compile-time callee -- a fact, correctly refused. The named-callee
   case is a real artifact but no corpus file exercises it; splitting the
   refusal would be speculative work. Revisit if a corpus file reaches it.
2. DONE. `until` lowers. The negation goes on the CONDITION, not the Projs:
   a first attempt swapped the body/exit Proj indices -- which the refusal's
   own comment ("would need the negated sense") seemed to invite -- and emitted
   the INVERSE program, `$i++ until $i >= 3` coming back as
   `while ($i >= 3)`, which hangs. The Proj index is a ROLE (0 body, 1 exit),
   a convention the deparser states outright and the backend shares, so the
   sense is negated where the condition is built and every consumer keeps one
   rule. `until !EXPR` needs a second case, since `Not` is not a comparison:
   drop the `Not` and rebuild an explicit truthiness test (`!!5` is 1, not 5,
   so the operand and its double negation are truth-equivalent, not equal).

   NO CORPUS GAP WAS REMOVED -- the census is still 17. This refusal was found
   by minimal reproduction while classifying the convergence GAP, and t/base,
   t/comp and t/cmd do not exercise it. A real lowering, not a coverage win.
3. The `continue`-block and function-exit-in-loop kinds are control flow the
   walker does not model. Real work, correctly refused today.
4. DONE. Reduced, classified as an artifact, and fixed.

   ROOT CAUSE, one line: OpMap declares `leaveloop => [2, ...]` -- pop two. At
   top level that never fires, because the main walk handles `leaveloop`
   itself (restore locals, step past) and never reaches _step. A branch arm
   had no such handler, so it fell through, honoured the pop, and underflowed.

   THE GUARD WAS RIGHT AND THE POP WAS WRONG. Bypassing the refusal gives the
   real `Stack underflow at StackSim.pm line 25` -- the crash in perl's own
   t/op/try.t that the guard was added to convert into an honest refusal. So
   this is fixed at the source and the refusal is gone, not relaxed.

   THE OLD GUARD MEASURED STACK RESIDUE, NOT THE LOOP. It refused on
   `stack_depth < 2`; the body is walked three times and only the leftovers
   differ:

       $s += $x     leaves 1 per walk   depth 3   passed
       print "x"    leaves 0 per walk   depth 1   refused

   and the prediction held both ways -- `print; $s += $x` passed while
   `print; print` refused, with nothing about the loop different.

   WHY IT HID FOR SO LONG, and why my first audit entry said "did not
   reproduce": t/from-optree-loop-in-arm.t pins loops-in-arms with a body of
   `$n = $n + $i`, one of the residue-leaving shapes, and my own probe used
   `$s += $i`. The existing coverage had exactly the blind spot I did.
   t/from-optree-loop-in-arm-effect-body.t now covers the effect-bodied forms.

   In comp/utf.t the enclosing branch is `next if $enc eq 'UTF-8'` (line 65),
   whose not-taken path holds the remaining `for` loops. `next` was incidental.

   Corpus: 17 -> 16 GAPs. comp/utf.t and t/op/try.t both translate.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
