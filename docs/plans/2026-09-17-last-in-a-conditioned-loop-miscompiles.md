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

SUPERSEDED. This was built in 91fc7c1 -- see "2026-09-20: producer half DONE"
below, which is the current state. Kept for the scoping record.

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

## Resolved 2026-09-18 (a8e8432): the cause was a PREDICATE, not the Regions

The previous section reported this as a Region-construction defect -- "two
Regions where the while path builds one, and the break's recorded bindings hold
the header Phi". That was the SYMPTOM. Reading the predicate rather than the
graph found the cause, and the arm-walk threading described above turned out to
be unnecessary.

### 1. The scan stopped at a block prologue

    last if C          other-> last
    if (C) { last }    other-> enter -> nextstate -> last -> leave

`_is_loop_control_or_exit` bounds its scan at `nextstate` -- correct in the
MIDDLE of an arm, wrong at its HEAD. It fired on the prologue's nextstate and
returned 0 before reaching the `last`, so the guarded-STATEMENT handler claimed
`if (COND) { last }` and merged a break as an ordinary statement. That is why
the emitted loop had no `last` in it at all, and why the increment appeared to
"sink below the if": the arm had been merged, not broken out of.

Fixed by skipping a LEADING enter/nextstate prologue only (the one-statement
bound stands everywhere else), plus the same view in the mid-body handler,
which tested ->other->name directly. New helper: _guarded_loop_control.

### 2. The foreach walkers never ran the soundness pass

Phase 5's exit-Phi construction lived inside _translate_while_loop alone:

    while (..) { $n++; last if COND }         refused (correct)
    foreach (@o) { $n++; if (COND) { last } } emitted 1 where perl gives 2

Lifted into _bind_break_exit_phis, run by all three walkers.

### Where this leaves it

    foreach (@o) { if (COND) { last } print ... }   LOWERS
    foreach (@o) { $n++; if (COND) { last } }       refuses, as while does

The ordinary early-exit search translates. A slot LIVE at the break is the
genuine multi-exit value merge and refuses in both loop forms, which is the
contract.

STILL OWED: the multi-exit merge itself (an exit Phi the deparser can render),
and `next` before `last`, which the committed test pins as refused.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## `next` before `last`: attempted 2026-09-19, reverted

Two findings, one of them a defect I introduced and should not repeat.

### THE 'exited' SIGNAL IS OVERLOADED

21776e8 made a `last` in an arm return `'exited'` -- the same string the
FUNCTION-exit path uses. They are different transfers: an exit leaves the
function and needs an exits list, a break leaves the LOOP and routes through
@break_projs. Every existing consumer reads one string and cannot tell them
apart, which is why the statement-modifier handler refused both:

    GAP: function exit inside a statement modifier in an if/else arm

A distinct `'broke'` signal fixes the ambiguity and lets that handler route a
break while still refusing a `return`. THAT PART WORKED -- the construct
translated. Worth redoing.

### WHAT DID NOT WORK: the break's control edge

The modifier handler pushed `$mod_sim->control` as the break Proj. Measured,
that is the NEXT-GUARD's arm, not a break-specific edge:

    If 9 in=[4, 8]              the `next` guard
    Proj 10 = If 9 index 1      the continue arm
    Proj 15 = If 9 index 0
    Region 16 in=[15, 10]       <- merges a LEAVING arm with a CONTINUING one
    Region 11 in=[3, 10]        <- the exit takes Proj 10 as well

So one Proj feeds both the loop's exit and a body merge, and the exit Phi ends
up regioned on the body merge (Phi 23 rgn=16) where the deparser correctly
refuses it. A `next`-only loop with the identical Phi shape renders fine, which
is what rules the deparser out as the cause.

The break needs its OWN control edge out of the modifier's If, the way the
loop body's handler mints $taken_proj -- not the arm the walk happens to be
standing on.

### Established either way

- `'broke'` vs `'exited'` is a real distinction the code needs, independent of
  this case. 21776e8 introduced the overload; it is still there.
- A `return` in the same position must keep refusing, and the test pins it.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc

## 2026-09-20: producer half DONE (91fc7c1); deparser half scoped, not built

### What landed

`next` before `last` translates. Two causes, both as 726b343 predicted:

- The statement-modifier handler built an If (and so its own Projs) only for a
  void call or a die. A break is neither, so $mod_sim kept the OUTER control --
  after a preceding `next if C`, that guard's arm.
- A 'broke' arm fell through to the merge. 'exited' already skipped it; the
  break was folded back into the body and never reached the exit.

Result: `Region 15 in=[3, 14]` -- header-false Proj AND the break Proj,
structurally identical to the `next`-only loop that renders today.

### The deparser half: what it needs, measured

The refusal is `a Phi whose region is a Region rather than a Loop` on

    Region 25 in=[23, 24]    Proj 23 = If 9 (next) index 0
                             Proj 24 = If 13 (break) index 1
    Phi 26   rgn=25          the accumulator at that join

which is an ORDINARY body merge -- the `next`-taken arm and the
break-not-taken arm are the two paths that reach the bottom of the body. Only
the route to it is unusual.

_emit_if's break branch returns `undef` as its join, so the walk never treats
Region 25 as one and `_join_phis` never binds Phi 26.

ATTEMPTED AND REVERTED: returning the rest arm's converged Region instead of
undef. Necessary but not sufficient -- the Phi also has to be BOUND, and
`_join_phis` maps each Phi input to an ARM. Here one arm is a `last` that
never reaches the join and the other comes from a DIFFERENT If, so the arm map
it expects does not exist in that shape. Building one without tracing
_join_phis would have been guesswork.

DONE in 580ab93 -- see "Closed 2026-09-21" below, which also records where
this scoping was wrong. Kept as written.

NEXT STEP for whoever takes it: trace _join_phis' predecessor matching (it
reads the Phi's `predecessors` field, "matched to its arm by the graph rather
than by position") and decide whether a break-shaped join can supply that map,
or whether this join wants a different binder.

Three round trips are TODO'd in t/deparse-loop-exit-phi.t with this reason --
including `last` before `next`, which fails the same way and which I had
assumed worked until the test said otherwise.

## Closed 2026-09-21 (580ab93): the deparser half, and a second cause

`next` before `last` round-trips. TWO causes, and only the first was the one
scoped above.

### 1. The break path never bound its join -- and the arm map DID exist

`_emit_if`'s break branch returned `undef` as its join, so `_join_phis` never
ran over the merge below it.

The scoping above stopped at "one arm is a `last` that never reaches the join
and the other comes from a DIFFERENT If, so the arm map it expects does not
exist in that shape." That was wrong, and the graph says so:

    Proj 27 = If 14 (next)  index 0
    Proj 28 = If 18 (break) index 1
    Region 29 in=[27, 28]
    Phi 30   in=[4, 26] pred=[27, 28]

Only the REST arm is a predecessor of Region 29; the break arm leaves the
loop and is not one. So the map needs ONE entry, not two -- exactly the
lone-arm shape `_join_phis` already supports, where the predecessor with no
arm seeds the declaration and the present arm assigns. No new binder.

The instinct to trace before building was right; the conclusion drawn without
tracing was not.

### 2. `_reaches_region` was transitive through a nested `If`

NOT PREDICTED ANYWHERE ABOVE, and the more serious of the two.

The scan stopped at a Region but walked straight through an `If`, so the
next-guard's arm found the loop exit through the LATER branch:

    Proj 15 -> If 18 -> Proj 19 -> Region 20 (the loop exit)

The `next` was therefore classified as the break and emitted as `last`, and
the real break was never reached. Measured: perl prints 4, the emitted
program printed 0.

Fixing cause 1 alone would have SHIPPED that -- a silent wrong answer in
place of an honest refusal, which is the trade this project's contract
forbids. It surfaced only because the round trip ran after the binding
landed. Bounded at a nested `If` now, the way it was already bounded at a
nested Region.

### The third TODO was filed under the wrong cause

`last` before `next` was TODO'd here as the same deparser defect. It is a
PRODUCER refusal:

    GAP: a loop control (`next`) inside a branch arm is not yet lowered
         -- only `last` carries an exit edge

perl prints 13. Repinned in t/deparse-loop-exit-phi.t as the producer refusal
it is, asserting that message. Still open, tracked as its own defect rather
than as this one.

Two refusal tests here had gone stale in the way
[[a-refusal-test-must-name-its-cause]] describes -- t/deparse-last-emits-a-
break.t's subtest pinned the producer refusal, then the deparser one, and is
now the round trip its own comment said it was heading for.

### Evidence

Suite 350 files / 1563 tests green. Corpus census measured on BOTH sides of
the change and unchanged at 12 round-trips / 10 differs / 15 refused: no
t/base, t/comp or t/cmd file reaches this shape, so the gain is in the suite,
not the corpus.

## Status 2026-09-21

This document owes nothing further. The remaining `next`-in-a-branch-arm
refusal is a producer defect with no plan doc of its own yet.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc