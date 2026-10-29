# Census cause: @_ read as a list, an alias that is only read, and an inert /u (357 -> ?)

**Cause:** "direct call to X: callee writes $_[N]" held 112:
`sub e { join ",", map { c($_) } @_ } e(@a)` under `use v5.36`.
- It needed three things, and round-trips in probes once all are in place.
- It is the triage's row 6. W1's refusal had moved its next refusal to
  "flattens into @_".

## What changed (chalk only)

- **@_ read only as a list is built flattened.** Read only as a list means
  no position, no slurpy and no write. An array argument, or a list a
  call returns, is its elements (`_emit_flattened_array_of`). A hash is
  still refused, because that helper does not flatten one. W1's guard
  skips exactly this shape.
- **A LocalAlias of `$_` to an `@_` element** (`for (@_)`, `map {...} @_`)
  counts as a write only where `_may_write_topic($graph)` holds. That
  helper looks for a store to `$_` (EntryWrite, Assign), or an s///,
  tr/// or chomp of it, in the callee or any direct callee, recursively.
  Any method, indirect or dynamic call counts as one, since its body is
  not known. The producer turns reads of `$_` in such a loop into reads of
  the `@_` element, so a write through the alias would appear as a store
  there, and is still refused.
- **`/u` (unicode_strings, set by `use v5.12`+) is dropped where it changes
  nothing** (`_without_inert_u`). It decides only how `\w \s \d` and their
  negations, POSIX classes and `/i` treat a byte past ASCII. A pattern
  with none of those, and flags without `i`, matches the same bytes either
  way. Every regex in a `use v5.36` program was refused before; `/\w/u` is
  still refused.

## Lessons

- A refusal can hide two more behind it. Probe the case after each step;
  the triage's "next refusal" column is a first guess.
