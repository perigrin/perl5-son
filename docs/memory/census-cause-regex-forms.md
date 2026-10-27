# Census cause: regex forms (literal braces, a constant-string pattern)

**Causes:** "malformed regex counted quantifier" (379) and "Match rhs
(op=Constant) is not a qr// literal" (384, 010).

**Round-tripped:** 379 (281), 384 (282). 010 next hits `/g`.

## What was done

- **Braces:** a `{` that opens no count (`{n}`, `{n,}`, `{n,m}`, `{,m}`) is a
  literal brace, and so is a lone `}`. `{,m}` means `{0,m}`. Blanks may stand by
  the braces and the comma (perl 5.34), so `a{ 2 }` is still a count. My first
  version read `a{ 2 }` as literal text, a WRONG answer caught by a probe.
- **Constant-string pattern:** `/$p/` with `$p` folded to a constant string uses
  that string as the pattern, with the match's flags. B::SoN's runtime-pattern
  Match carried no flags, so `/$p/i` matched case-sensitive. Fixed in the
  producer (Match has a `flags` field, in its hash), and chalk refuses a string
  pattern whose flags were not sent.
- **Empty s/// pattern refused.** In perl it is the last successful pattern.
  B::SoN also sends `s/$p/X/` that way, with `$p`'s value in the replacement
  (producer bug; chalk printed "babcb" for "aXcb").

## Lessons

- A test can be ambiguous: `"x{,3}" =~ /x{,3}/` matches under both readings.
  Write the case so only the right reading passes (`"x" =~ /^x{,3}$/`).
- `"^a.c$"` in a double-quoted test interpolates `$"`, so the program was a
  syntax error and perl printed nothing. Use q() for patterns in tests.
- Producer bugs found: an internal "Stack underflow" on two matches in one print
  list; `s/$p/X/` with the pattern lost (both in the report list).

## qr// flags and stringification (pin 286)

**Round-tripped:** 389, 010 (284 -> 286).

- A qr// printed is `(?^FLAGS:pattern)`. The Coerce Regex->Str of a regex
  Constant is that text as a constant.
- **Wrong answers found (pre-existing):**
  - `"a" =~ qr/A/i` gave 0. B::SoN sends a qr Constant's flags, but the chalk
    loader dropped them and the match compiled with "". Constant now has
    `flags` (in its hash), and the match uses them (and refuses /i, which the
    G6 compiler lacks).
  - `split /x/i` split by "x" alone (2 for 3). The producer sent no flags on
    split's pattern. The producer now sends them (absent = none, as for qr//),
    and chalk refuses split by a flagged regex.
- Lesson: a flag is part of the pattern. Every place a pattern is read
  (RegexMatch, Match through qr, split, s///) must take its flags or refuse.
  Audit them together, not one at a time.
