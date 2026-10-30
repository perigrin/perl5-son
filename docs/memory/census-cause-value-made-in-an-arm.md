# Census cause: an inlined sub's value made inside one of its arms (373 -> 374, pin 82d8c69a)

**Cause:** "an inlined sub's value is made inside one of its arms". It
held 156 and 205.

## 156: an eval's join (chalk 82d8c69a)

`sub f { my $n = 0; eval { for (...) { $n = $x; die if ... } }; return $n }`

- **What went wrong.** `_lower_inlined_structure` walks the callee's
  main path back from its Return to tell an arm's value from a
  main-path one. The walk stopped at the eval's join Region, which has
  no `head` and no `control_in`. So the loop's exit read behind it
  looked like an arm's value.
- **The fix.** An eval join with one input (where the body ended; a die
  goes to the catch) is a step of the path, and the walk goes on
  through its input.
- The same body at top level already lowered (probe ib4). Only the
  inline check refused it.

**Round-tripped:** 156.

## Still refused

- **205:** a nested `while` with `next` and no eval: a different shape.
