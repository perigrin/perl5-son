# Census cause: `<DATA>` (a filehandle that is not a lexical)

**Cause:** "a filehandle that is not a lexical `my $fh` is not lowered". It held
014, 363 and 364.

**Round-tripped:** 363, 364, and 045 too (277 -> 280). 014 next hits qx``
(BacktickExpr).

## What was done

- B::SoN already sends the text after `__DATA__` / `__END__` as the JSON's
  `data_section`. The loader keeps it in `$Chalk::IR::Serialize::JSON::DATA_SECTION`.
- `_handle_cell` for the `DATA` glob is an entry-block cell holding the
  existing in-memory read handle (`{data, len, pos, target}`), open on that
  text. List and scalar reads, `eof`, and reads inside a sub all use the
  existing readline machinery.
- Refused: no section; DATA in a method body (its own function, which would get
  its own handle).

## A wrong answer found on the way (pre-existing)

`print @lines` after `my @lines = <$fh>` printed the COUNT. B::SoN hands print a
list made at run time as one `Coerce[List->Str]`, and chalk read it as an
aggregate's scalar. `print sort @a`, `print keys %h` and `print map {...} @a`
were all wrong the same way. Now such an argument prints its elements, joined
with nothing.

**First attempt broke 228/249 (DIFFERS 2):** `print scalar(ff())` is also a
`Coerce[Array->Str]` by the time chalk sees it, but the producer wrote
`Unknown` and Analysis narrowed it. The Coerce now keeps the producer's
`wire_from`, and only one the producer called a list is joined.

## Lessons

- Analysis rewrites wire facts (from_repr) in place. When the original matters
  to a later decision, keep it on the node, or the decision reads the guess.
- The census DIFFERS gate caught what the probes did not: run the full check
  even when the targeted cases pass.

Tests: chalk `llvm-data-reads-the-data-section.t`,
`llvm-print-of-a-list-made-at-run-time-prints-its-elements.t`.
