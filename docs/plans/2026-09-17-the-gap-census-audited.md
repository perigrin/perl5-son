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
    1  a loop inside a branch arm                    ARTIFACT (reduced; see 4)

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

    genuine facts   5 of 17   glob-from-a-Call (x2), undef(*GLOB),
                              `write` format, map-arity via &{$sub} (x2)
    artifacts      12 of 17
    unclassified    0 of 17

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
4. REDUCED AND CLASSIFIED: ARTIFACT. My "did not reproduce" was wrong, and
   wrong for an instructive reason -- the probe I used happened to miss the
   trigger by one property.

   It reproduces in four lines, from the most obvious shape there is:

       my $c = 1;
       if ($c) { for my $x (1, 2) { print "x$x\n" } }

   THE TRIGGER IS A CONTROL-ADVANCING EFFECT IN THE BODY, not the loop form
   and not the branch. Measured, all inside `if ($c) { for ... }`:

       $s += $x            translates
       push @a, $x         translates
       print "x\n"         GAP
       warn "w\n"          GAP

   and the same `print` loop OUTSIDE a branch translates. So it is the
   combination: a loop in a branch arm whose body advances the CONTROL chain.
   My earlier probe used `$s += $i`, a pure accumulate -- one of the two forms
   that works.

   In comp/utf.t the enclosing branch is `next if $enc eq 'UTF-8'` (line 65),
   a statement-modifier loop-exit whose not-taken path holds the remaining
   `for` loops. `next` is incidental: `next if` alone translates, and so do
   several statements after it.

   An ARTIFACT: nothing about the program is unknowable. The walker's branch
   handling does not thread a nested loop's control chain, which is why the
   leaveloop "arrived without its operands".

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
