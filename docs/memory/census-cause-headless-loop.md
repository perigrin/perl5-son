# Census cause: a loop with no header test (`while (1)`)

**Cause:** "could not find loop condition". It held 122:
`while (1) { $x = $x + 1; last if $x == 3 }`.

## What chalk did

- **The test search.** chalk looks for a Loop's test in two places: a
  comparison pinned to it, or the first comparison on one of its
  loop phis.
- **No test to find.** `while (1)` has neither, because perl folds the
  constant away.
- **Refused or wrong.**
  - With no comparison on a phi, chalk refused the loop.
  - With one, the fallback took a body comparison as the loop's test.
    `while (1) { $s .= "a" if $x < 2; ...; last if ... }` printed
    `f 2 aa` for perl's `f 5 aa`: a silent wrong answer.

## What the producer did

- The while walker took the first `and`/`or` it met as the loop's
  condition. A `while (1)` body's first `STMT if C` became the loop's
  test (NumLt pinned to the Loop), and the `.=` ran on every pass.
- **Fix.** A written condition's `and` enters the body through
  `other`, so its other IS the enterloop's `redoop`. Any other
  `and`/`or` is a guard.
  - `$LOOP_REDO` is handed from the enterloop site through
    `$NEXT_LOOP_REDO`. `_translate_while_loop` takes and clears it, so
    postfix loops see none.
  - The claim site sets `$condition_fired`, clears the op's visited
    mark and `redo`es, so the guard handlers build an If.
- Test: t/deparse-a-while-one-guard-is-not-its-condition.t. It checks
  the graph's shape, because the deparser refuses a Phi at a body
  Region in a headless loop by name.

## What changed in chalk

- `_lower_loop_condition`: a loop with no exit Proj is 'true'.
- `_loop_body_start`: the body starts at Proj 0, or at the Loop itself
  when it has no Projs. `_collect_branch_body` walks a Loop root's
  consumers.
- The header branches to the body unconditionally. The exit merges
  have one input per `last` only, with no header edge.
- Test: t/bootstrap/ir/llvm-a-loop-with-no-header-test.t. Its lli runs
  under `timeout 20`, because a broken loop hangs.

**Lesson:** a heuristic fallback ("first comparison on a phi") gives a
wrong answer when the structure it assumes (a header test) is absent.
Ask whether the structure is there before guessing at it.
