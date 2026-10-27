# Census cause: a list assignment into scalars from a list that flattens

**Causes:** "PadAccess has no VarDecl input" and "a list assignment to a
PadAccess that is not a scalar kept in memory is not lowered" (090, 167, 168,
and any `my ($a, $b) = f()`).

**Round-tripped:** 090, 167 (pin 302).

## What was done

- **Producer:** `my (...) = VALUE` where VALUE has no positions (a call, a
  short-circuit, a merge, a match: `$single_call`) floated -- no control
  input, no consumer -- so nothing walking the chain bound the targets, and a
  call's effects had no place (`my ($s) = f(); print "x"` must print f's
  output first). It is now pinned on the control chain, as the
  declared-earlier form already was. NOT for `my (...) = @_`: consumers bind
  that floating form themselves, and pinning it moved Deparse's binding after
  a read (six deparse tests).
- **Chalk:** a list assign into a scalar PadAccess with no VarDecl gets a
  %Slot cell per target NODE (`_list_cell`, keyed by id, not name: two
  `my ($x)` in nested scopes are two variables); a read of that node loads
  it. A value that may flatten is flattened into an array; target i takes
  element i, undef past the end.
- **`defined` of a cell-backed variable stamped Unknown** read "always
  defined" (an undef `$b` from `($a, $b) = (7)` printed "d"). It reads the
  cell's defined bit now.

## A pre-existing producer miscompile found on the way

`sub f { my $n = shift; ($n, 1) }` returned ($n, $n, 1): the elided-return
path of `_exit_record` popped the WHOLE simulated stack, which still held the
void assignment's value (perl resets the stack at each statement). Now it
takes only the trailing list's operands (`_leavesub_list_arity`). Deparse
printed "3 4 4 1" for perl's "2 4 1".

## Still open

- `my @a = f(4)` over `return ($n, $n * 2)` emits invalid IR (pre-existing).
- `split` into N targets (an implicit limit) and a list assign read as a
  scalar (`$n = (($a, $b) = f())`) are refused by name.

## Lessons

- A probe of the newly lowered shape found a producer bug the census never
  could: the wrong extra element was harmless until something read the list
  positionally. New lowering exposes old upstream errors -- probe it with
  helpers that do real work (shift, arithmetic), not just constants.

Tests: chalk `llvm-a-list-assign-from-a-flattening-list.t`; producer
`from-optree-a-my-list-from-a-call-is-on-the-chain.t`,
`deparse-an-elided-return-is-its-own-list.t`.

## A sub called in list context, read as its list (chalk ebff3eae)

Found by probing the shapes around this cause; no corpus case moved.

- `print f(4)` (f shifts and returns a list) printed the count: print read
  the call through its stamp, which Analysis had narrowed to the sub's scalar
  face. `"@a"` after `my @a = f(4)` emitted invalid IR: join walked the
  callee's list statically and lowered an element as the array. Both now
  flatten what the inlined sub returned when the call's `want` is list.
- Lesson: a call's STAMP after Analysis is its scalar reading; its `want`
  (from the wire) is what says which context it is in. Read `want` where the
  context matters.

Test: chalk `llvm-a-join-over-a-subs-list.t`.
