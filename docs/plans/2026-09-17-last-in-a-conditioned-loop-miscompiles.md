# `last` in a loop with a header condition is dropped

Found while scoping the `continue` GAP. NOT a GAP -- a silent miscompile, which
the project ranks worse than a refusal.

## Measured

    for my $i (1..5) { last if $i == 4; $s += $i }
      perl      6
      emitted   15        the `last` is gone

    my $i=0; while ($i<5) { $i++; last if $i==4; $s += $i }
      perl      6
      emitted   615       (also prints twice)

    for my $i (1..5) { next if $i == 2; $s += $i }
      perl      13
      emitted   13        MATCH -- `next` is fine

## Why the graph is wrong

    for my $i (1..5) { next if $i == 2; last if $i == 4; $s += $i }

      19 If    [16, 18]     the `next` test
      22 NumEq [14, 21]     the `last` test -- NO CONSUMER, no second If

The comparison is built and nothing reads it: no exit edge, no Region. The
deparser then renders a loop carrying only the `next` branch, and additionally
emits `my $phi27 = $phi4;` BEFORE `$phi4` is declared.

## Why coverage missed it

t/deparse-infinite-loop-with-last.t pins `while (1) { ...; last if C }` -- the
PROJLESS form, where there is no header condition and the exit lives inside the
body as an If hanging off the Loop. That path works and is tested.

    while (1)      { ... last if C }   MATCH    no header condition
    while ($i<5)   { ... last if C }   DIFFERS
    for (1..5)     { ... last if C }   DIFFERS

So the defect is specifically a loop that has BOTH a header condition and a
`last` -- two exit edges -- and the second one is silently discarded.

## Relationship to the `continue` GAP

Same underlying shape: a loop region with more than one exit. The bare-block
`continue` GAP refuses because `next` and `last` have different destinations
(measured: `next` runs the continue body, `last` skips it). Here the second
exit is not refused, it is dropped. Fixing the exit modelling probably wants to
come before the continue work rather than after it.

## Unknown

Whether chalk miscompiles this today, and whether the corpus hides it behind
earlier first-failures. Neither measured.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Correction: the refusal exists, it just misses the conditional form

perigrin asked what `for my $i (1..2) { say $i; last; }` prints. One line --
and checking it against the producer shows the UNCONDITIONAL form is already
refused, honestly:

    for my $i (1..2) { say $i; last; }
      GAP: loop control (last) inside a loop body not yet lowered

    for my $i (1..5) { last if $i == 4; $s += $i }
      no GAP; perl 6, emitted 15

So this is not "last is unmodelled". The refusal is built and correct; the
statement-modifier form evades it, because `last if COND` hangs the `last` off
an `and`'s OTHER branch rather than the ->next chain -- the same structure the
continue exit-scan had to learn to follow:

    f  and(other->g)
    g      last          <- exec order runs f -> h, skipping it

A linear scan sees no `last` and lets the loop through, and the comparison is
then built with no consumer.

That makes the fix much smaller than this doc first implied: teach whatever
detects loop control to follow `other` branches, so the conditional form
reaches the SAME refusal the unconditional one already gets. That converts a
silent miscompile into an honest GAP without needing exit modelling at all.

Lowering `last` properly is still the larger piece, and unchanged.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Status 2026-09-18: correctness closed, ONE LOWERING STILL OWED

    deparser inlines the break arm     FIXED    d85b24c
    foreach drops the break            FIXED    0651819
    last in a branch arm               REFUSED  72a4da7   <- lowering NOT built

No known silent `last` miscompile remains. What is NOT built is the lowering
behind the third: an arm walk that can carry a loop exit edge.

### What that refusal costs

    foreach (@o) { if (COND) { last } }      the ordinary early-exit search

does not translate. It is a common shape and it is what comp/require.t needs
(its `foreach { if ($_ eq "PERL_DISABLE_PMC") { $no_pmc=1; last } }` is why the
corpus went 16 -> 17 when the refusal landed -- that file had been translating
WRONGLY, measured `perl 2, emitted 3` on the counted form).

### What the lowering needs

_walk_loop_body already does this correctly: it builds the If, routes the
guard-taken arm through @break_projs, and Phase 5 adds that Proj as an extra
predecessor of the exit Region. An arm walk reaches none of it -- _walk_branch
has no $loop_node, no @break_projs and no exit Region to attach to. So the work
is threading that loop context into the arm walk and routing the break out
through it: the same machinery, reachable from one more place.

### Why it is not scoped yet

Two things to settle before estimating:

1. _walk_branch has 30 call sites, and MOST HAVE NO LOOP CONTEXT -- eval arms,
   ternaries, try/catch. The parameter has to be optional and behave correctly
   when absent, which is where a careless version would reintroduce the drop.
2. The while path's SOUNDNESS CHECK -- the one that GAPs when a slot rebound
   before the break is read after the loop -- has to apply from the arm too.
   Without it a multi-exit value merge becomes a wrong answer rather than a
   refusal.

DEFERRED, NOT SKIPPED. Recorded here because it was left implicit when the
session moved to the deref-count defect, and an unlabelled deferral drifts.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Scoped 2026-09-18: smaller than estimated

Both open questions measured.

### 1. Call sites: 12, not 30, and only TWO need loop context

    660    _translate_from                  dor/or arm
    832    _translate_from                  arm with exits
    1055   _translate_from                  try body
    1083   _translate_from                  catch body
    8185   _scout_condition_mutated_targs   scout
    9308   _walk_loop_body                  REST-OF-BODY after a next/last guard
    9431   _walk_loop_body                  guarded statement arm
    10310  _handle_entertry                 eval body
    10404  _handle_cond_expr                ternary arm
    10700  _walk_branch                     recursive
    10905  _walk_branch                     recursive
    11896  _walk_subst_replacement          s///e replacement

My earlier "30 call sites" was a grep count including the definition and
comment mentions -- wrong, and it inflated the estimate.

The two that matter (9308, 9431) are both INSIDE _walk_loop_body, where
$loop_node and $break_projs are already in scope. The other ten are eval arms,
ternaries, subst replacements and scouts, where a `last` genuinely has no loop
to exit and the current refusal is the right answer. Two are recursive and
must propagate whatever they were handed.

So the parameter is optional, defaults to absent, and only two call sites pass
it -- much narrower than "thread loop context through the whole walker".

### 2. The soundness check is ALREADY where it needs to be

Phase 5 of _translate_while_loop runs over @break_projs after the body walk:
for each break, any slot whose break-point binding differs from its header Phi
gets an exit Phi over [header, break-value]. DCE drops it when the slot is
dead post-loop; a live read becomes a loud GAP rather than a miscompile.

That runs on the COLLECTED list, not at the point of collection -- so a break
recorded from an arm walk is checked by the same code with no change. Question
2 dissolves.

### The remaining work

Pass $loop_node and $break_projs into _walk_branch (optional, propagated
through the two recursive sites), and give it the same guarded-`last` handler
_walk_loop_body has: build the If, push {proj, bindings} onto $break_projs,
continue the rest on the not-taken arm. When the parameter is absent, keep
today's refusal.

The bare-`last` refusal added in 72a4da7 becomes conditional on the same
parameter.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## Attempted 2026-09-18, reverted: the bindings are wrong at the break

The scoping held -- the threading is two call sites, the parameter is optional,
and Phase 5's soundness pass needs no change. `last;` reaches the emitted
program in the right place. What does NOT work is WHICH VALUES the break
carries.

    foreach (@o) { $n++; if ($_ eq "HIT") { last } }
      perl 2, emitted 1

      while (...) {
        if (...) { last; }        <- correct
        my $phi4_next = ($phi4 + 1);   <- the $n++ sank BELOW the if
        ...
      }

The increment ran after the break in the emitted order, so the breaking
iteration does not count it. The graph shows why: TWO Regions where the while
path builds one (16 over [3,15] and 21 over [15,20]), and the break's recorded
`bindings` hold the header Phi rather than the incremented Add.

Reverted rather than shipped -- a wrong answer is worse than the refusal it
would replace.

### What the attempt DID establish

THE LOOP BODY IS WALKED TWICE and the scout pass has no collector. A scout runs
with $break_projs undef BY DESIGN (it measures mutated slots and does no
control wiring), so a refusal reached from the arm walk fires THERE and kills
the translation before the real pass runs. Measured: both refusals came from
the scout, `bp=no` in both. Any future attempt must let the scout tolerate a
break and only RECORD one on the real pass -- which also means neither
$loop_node nor $break_projs is a sound "am I in a loop" test, since the scout
has neither. An explicit flag is needed.

### Still owed

Same as before, plus: the break must record the bindings AS OF THE BREAK
POINT, and the arm's control must join the loop's exit Region rather than
building a second one.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
