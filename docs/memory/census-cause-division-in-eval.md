# Census cause: a division that may die inside a block eval (339 -> 341)

**Cause:** "a block eval whose body makes a value that may die (a division
by what may be zero, an element reference) is not lowered" held 2 cases,
006 and 062. Both round-trip now (pin b3f5636d).

## What changed (producer 0fbb082, chalk b3f5636d)

- Producer: a Divide/Modulo that may die carries `eval_id` (the eval body
  it is made in), `file` and `line` (the nearest nextstate). Both fields
  are part of its content hash, so two divisions at different sites stay
  two nodes. A block eval is marked may-die only when a may-die node made
  in its body is *unreachable* from the body's control, memory or value.
  chalk lowers the reachable ones as that eval's own die. An unused one
  would be dropped where perl dies, so it stays refused (probe ud6).
- chalk: `_die_on_zero` inside the division's own open eval frame stores
  "Illegal division by zero at FILE line N.\n" in $@ and branches to the
  catch. A division naming an eval whose frame is not open is refused.
  This covers a division made before the eval but lowered inside it.
  `close_eval` lowers the merge values while the frame is still open.

## Ordering

The producer change shipped without chalk's would be a wrong answer
(062 printed the uncaught path). Both were checked together and pushed
in one step: chalk first, then the producer.

## What they hit next

Nothing: both round-trip. The same mechanism (a node naming its eval)
is the route for an element reference that may die in an eval.

## Lessons

- A may-die flag on a whole eval is too coarse. Tag the node with its
  eval, and refuse only what the lowering cannot place.
