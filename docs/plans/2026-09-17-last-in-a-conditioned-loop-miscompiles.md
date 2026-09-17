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
