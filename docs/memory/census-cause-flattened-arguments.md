# Census cause: an argument that flattens into @_ (3 cases; 0 round-tripped yet)

**Cause:** "direct call to X: an argument stamped Array flattens into @_,
which inlining does not build". It held 145, 174 and 199.

## What changed (chalk)

- **@_ read only by position is the arguments flattened** (57935945). This
  applies when there is no write, slurpy, signature or list read. The
  arguments are flattened once, and each positional read is the element at
  its index: `_emit_array_slot_at`, undef past the end, read as its own repr.
- **A Concat operand nothing typed is coerced from what it was lowered as.**
  `$b // 'u'` of an argument held as a Scalar was a %Slot taken for a %Str,
  and lli rejected the module, whether the argument was flattened or not.
- **A nested short-circuit nothing typed has its arms' repr** (f659bc6b,
  `_shortcircuit_operand_repr`): `$c && ($a && $b)` from a fall-off.
- **A jump merge's non-scalar arm leaves its Phi unbuilt** (49a267c4). A
  scalar caller of a sub with a bare `return` reads only the scalar face;
  a read of the list face is refused by name.

## What they hit next

- **145** `$_[1] = 42` and **199** `$_[0] = 9` write through @_ into a
  flattened argument. Aliasing into the caller is not built, so they are
  still refused by the same message, by design.
- **174** also calls `my @l = f(1, "Q", 0)`. In list context, a bare
  `return` is the empty list: the merge of a jump nothing typed with a List
  arm. That is refused by name.

Tests: chalk `llvm-a-flattened-argument-read-by-position.t`,
`llvm-a-nested-short-circuit-nothing-typed.t`,
`llvm-a-bare-return-read-as-a-scalar.t`.
