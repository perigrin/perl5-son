# Future: value types (TypeScript-style literal types)

Deferred 2026-11-08 by perigrin; to be revisited.

## The idea

Types that are single values, as TypeScript's literal types: `True` and `False`
under `Boolean`, and beyond them literal strings and numbers (`"GET"`, `0`),
joined into unions (`"GET"|"POST"|"PUT"`).

## Why perigrin wants it

- Ad hoc enums: a Perl string constant used as a tag, a mode, a state, typed
  as the set of its values rather than as `Str`.
- "A bunch of other things Perl is often used for": dispatch on a string key,
  option hashes, status codes, the values a `//` or `||` default can take.

## What was decided now

- Defer `True`/`False`. Today they buy little: `False|Int` still joins at
  `Scalar`, and Context/T2 test `eq 'Boolean'` by name, so each new type needs
  mapping, as `Maybe[T]` maps to `Scalar` (`%Slot`).
- They pay off together with truthiness narrowing: in the true arm of `if (X)`,
  X loses its false values, so `False|T` gives exactly `T`.

## Facts to start from

- `Maybe[T]` (= `T|Undef`) is in both lattices as rules, not tree edges:
  chalk `TypeLibrary` and producer `SoN::IR::Stamp` (2026-11-08).
- `print` never returns false: it is `&PL_sv_yes` or `&PL_sv_undef`
  (pp_hot.c pp_print). So with value types it is `Maybe[True]`.
- `A && B` is (A's false values) | B. `defined X && X` is `False|T`, where T is
  X without its Undef.
- pvm's `internal/parse/declarations/CORE.tpm` writes builtin returns as unions
  (`Boolean|Undef`, `Int|Inf`), a source for literal and union types.
