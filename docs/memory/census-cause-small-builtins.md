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

## blessed() and isa (pin 291)

**Round-tripped:** 058. 180 next hits a method call on a run-time class stamped
Unknown (`blessed($_) && $_->ok`).

- `_class_of_value`: a reference's class from the bless table, or a Scalar's by
  its tag. Not a reference: not blessed. A class's object stops (as ref()).
- blessed: that class, boxed, or undef. Producer: `blessed => 'Scalar'`.
- isa: blessed && class eq C (memcmp).
- **A wrong answer found by a probe:** `use parent -norequire, "A"` sets @ISA
  in a use block, which the loader drops ("n" for perl's "y"). The loader now
  records `%USED_MODULES` from the use blocks it lets through. isa refuses with
  `parent`/`base` used, or any @ISA named in the program.
- Lesson: a dropped `use` block is not nothing. Anything it sets up
  (inheritance, exports, pragmas) is invisible downstream, so record which
  modules were used and let consumers refuse on them.

## Hash slice as a value, chomp/chop (pin after 291)

**Round-tripped:** 303 (hash slice), 137 (chomp). 291 -> 293 at check g150.

- A hash slice used as a list value (`@h{qw(a b)}`) is its values in key order:
  `_emit_flattened_array_of([$slice])`, the same path a list of an array takes.
- chomp removes one trailing "\n", chop the last character. chomp's value
  (ChompValue) is the count removed (0 or 1). chop's value is the removed
  character, which is refused.
- Tests: chalk `llvm-a-hash-slice-is-its-values.t`, `llvm-chomp-takes-one-newline.t`.
- Note: the check script's census reports the string-eval cases and 015 as
  LOAD_FAIL ("no program graph with a return"); the pin census counts them as
  GAP. Not new; compare with the previous check, not with zero.

## ref() of a glob reference, localtime (pin 300)

**Round-tripped:** 408, 312, 011 (297 -> 300).

- `ref(\*FH)` is GLOB. A GlobRef has no machine type, so the bless table
  cannot key on one: refused where the program blesses a GlobRef.
- `localtime(TIME)` through libc `localtime_r`: a list is struct tm's first
  nine ints (perl's order); a scalar is `strftime("%a %b %e %H:%M:%S %Y")`,
  perl's ctime text. Tests use fixed times (same libc and TZ as perl).

Tests: chalk `llvm-ref-of-a-glob.t`, `llvm-localtime.t`.
