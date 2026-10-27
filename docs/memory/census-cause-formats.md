# Census cause: `write` and formats

**Cause:** "direct call to 'main::__FORMAT__:main::STDOUT' has no resolved
callee". It held 293 and 294; both round-tripped (270 -> 272).

## What was done

- B::SoN makes a format a graph of `formline` calls and `write` a direct call
  of it. **Analysis** `_attach_formats` resolves that call to the graph (as
  for an anonymous sub).
- **Lowering** `_lower_formline` renders each picture line:
  - `@<<< @>>> @|||` are one `snprintf("%*s%.*s%*s")`, with the value cut at
    its first newline (memchr) and then to the width;
  - `@##.##` is `%*.*f`, or `#`s when the number is too wide;
  - each line's trailing spaces are trimmed with a run-time loop.
- A `write` in void context still lowers its value: a format's last line *is*
  the graph's Return value.

## Refused by name

`^` fields, `~` and `~~`, `@*`, a number field over a value that may be
undef, `formline` outside a format, `select`, a `$~` or `$^` store, a
top-of-page format (producer: perl prints it first; no graph was even made for
it), and a format reading a lexical.

## Lessons

- **Producer bug (open):** `my $lex = "mine"; format STDOUT = @<<<<<< / $lex`
  -- main's graph has no store into `$lex` at all, so the format read undef.
- `($x =~ /re/ && $x =~ /other/)` resets `$1`: capture into a variable before
  matching again (the decimals came out 0).
- An alternation whose first branch can match empty (`#*(?:\.#+)?|<+`) never
  reaches the others.

Tests: chalk `t/bootstrap/ir/llvm-write-runs-the-format.t`; producer
`t/from-optree-write-with-a-top-of-page-format.t`. Probes fm1-fm8: ROUNDTRIP
or refused by name.
