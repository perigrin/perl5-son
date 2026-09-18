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
