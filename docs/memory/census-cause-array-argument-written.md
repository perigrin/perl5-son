# Cause: "an argument stamped Array flattens into @_, which inlining does not build" (2026-11-05)

- Held: pvm 199 (145 went with the ?: of lists, census-cause-call-on-ternary-of-lists.md).
  - The case: `my $n = g($c ? @$x : ())`, where g does `$_[0] = 9; scalar @_`.
- Built (chalk 5f40cdf0):
  - `$one_array` in `_lower_call_direct` covers one argument that is an
    array: `@$x` (PostfixDeref), a `my @a` (an ArrayLiteral with a symbol),
    or a pad `@a`. It applies only when the callee writes $_[N] and reads
    @_ as a list, with no shift, slurpy, signature or positional read.
  - @_ is a flattened copy. `_copy_out_written_args` stores each written
    $_[N] back to element N, but only if N is below the array's length.
    Past the end, perl grows @_ and not the array.
  - `_lower_call_on_each_arm` accepts arms that are such an array, or a
    one-element ArrayLiteral wrapping one.
- GRAPH POLLUTION, fixed in the same commit. The synthesized store-back
  nodes (factory `make`) register as consumers of real graph nodes. f was
  inlined twice, and the second `_scan_memory_shape` saw the first
  inline's Assign as an off-chain element store, so it refused every
  element read. `_unlink` now detaches them in all three store-back paths,
  the older scalar path included.
  - Lesson: a node made only to be lowered must be unlinked afterwards.
- A suite test (llvm-a-flattened-argument-read-by-position.t) pinned the
  old refusal. It now expects perl's answer.
- Result: 199 round-trips. Census 404 -> 405.
