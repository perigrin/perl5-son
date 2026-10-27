# Census cause: small builtins (lt/gt/le/ge, index, chr, ord, unshift)

**Causes:** "cannot lower op=StrLt/StrGt", "builtin index", "builtin chr",
"builtin unshift": one case each, all with no lowering at all.

**Round-tripped:** 017, 253, 334, 335 (286 -> 290).

## What was done

- **lt gt le ge:** `_emit_str_cmp` (the body of `cmp`) compared with 0.
- **index:** an internal helper `@chalk_index` (memcmp at each start, from the
  start clamped to [0, len]; an empty needle finds the clamped start; -1 when it
  does not fit). Helpers follow the `_need_X` flag + `_X_lines` pattern, emitted
  in the post-class re-emit, with the flag in @NEED_FLAGS so a method body's use
  reaches the module.
- **chr:** one byte for 0..255. Past that, perl makes a wide character, which a
  byte string cannot hold, so the program stops (exit 255): the rare-shape
  runtime-stop policy. **ord:** the first byte, or 0 for "".
- **unshift:** a new array of LIST (an array's elements appended whole) and then
  the old contents. Its header is stored over the array's, so the variable keeps
  its identity. It is an array-mutating call (`_is_array_mutating_call`), so
  reads before it freeze there.

## Lessons

- The long tail is many one-case builtins. Each is cheap if its semantics are
  pinned with edge cases in the test (index with "", a negative pos, a pos past
  the end, a needle longer than the string).

Tests: chalk `llvm-string-order-comparisons.t`, `llvm-index-finds-a-substring.t`,
`llvm-chr-makes-a-one-byte-string.t`, `llvm-unshift-puts-values-first.t`.
