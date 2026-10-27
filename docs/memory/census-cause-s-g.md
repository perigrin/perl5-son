# Census cause: s///g (regex flags 'g')

**Cause:** "s///g flags not yet supported" (111, 376) and "regex flags 'g'"
(388, 010: `m//g` with `pos()`).

**Round-tripped:** 376 (282 -> 283). 111 (`/ge`) is refused by name. 388 and
010 (m//g with pos) are still open.

## What was done

- `_lower_regex_subst_g`: a loop with three phis (`%Str` result so far, offset,
  count). Each pass matches against `(ptr + offset, len - offset)`, appends the
  text before the match and the replacement (literal text and captures, relative
  to the slice), and continues from the match's end. The tail appends the rest.
  A latch block gives the phis a fixed predecessor; the result is carried with
  `select i1 true` because the append helper names its own values.
- `RegexSubstCount` (s///'s value) had no lowering at all. It is the count, or
  "" for none (non-/g: zext of matched).
- Refused: a pattern anchored at the start, one that can match empty (perl steps
  over an empty match by its own rules), and a computed replacement.

## A wrong answer caught by the census (DIFFERS 1)

`s/(\d)/$1*10/ge` -- B::SoN sends a /ge replacement as a graph of its own
(`replacement_body`), with `replacement` "". The chalk loader dropped the field,
so the first /g version replaced every digit with "" ("abc" for "a10b20c").
The loader now keeps `replacement_body`, and any s/// with one is refused.

## Lessons

- An unknown wire field is silently dropped by the loader. A feature that
  starts reading a node in a new way must check that the node has nothing the
  loader ignores (here: `replacement_body` next to `replacement ""`).
- Captures in a /g replacement are computed once by B::SoN (RegexMatch +
  RegexCapture outside the loop): refused, not per-match.

Test: chalk `t/bootstrap/ir/llvm-s-g-replaces-every-match.t`.
