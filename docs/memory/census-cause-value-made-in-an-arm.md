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

## 205: a push in a loop with a `next` latch (producer, not worked)

Minimal: `while (...) { if (...) { ...; next } push @o, $x; ... } return "@o"`.

- **The bug.** The read after the loop (`join`) takes @o's memory from
  Phi 20, whose region is the loop's LATCH merge (the `next` arm and the
  body's end), which is inside the loop. There is no memory Phi on the
  loop header for @o, so the producer has dropped the loop-carried
  memory version. A zero-pass loop would need it: memory would be the
  entry's.
- **Chalk.** Refusing this is the sound answer.
- **The fix belongs in FromOptree's loop memory threading** (a loop
  whose body has a next-latch).
- **Without the next latch** (probe id1) the same nesting lowers.

# Census cause: shift of an Int array read by an Assign (151, not round-tripped)

- **What lowers now** (chalk, after 82d8c69a): an Int shift is lowered
  as its Slot when every value use keeps the undef. Those uses are a
  Coerce, a Defined, a numeric compare, or a store to a location
  variable. `while (my $n = shift @w)` at top level and a shift past
  the end now give perl's answer.
- **A plain (non-location) variable stays refused.** Allowing it gave a
  silent wrong answer, `<><>` for perl's `<1><2>`. The rebind stored the
  Slot, and the untyped read of it (passed to an inlined `g`) took it
  for an Int.
  - **The fix:** record the stored repr for the VarDecl (`_vd_repr`) so
    the read knows. 151 is exactly this shape, inside a sub.
- **Also fixed:** `_lower_icmp_int` read its operands' reprs before
  lowering them. That was the same lesson a fourth time.
