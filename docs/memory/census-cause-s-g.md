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

## m//g and pos() (pin after 283)

**Round-tripped:** 388. 010 has more in it (`tr`, `split`, etc.); recheck.

- Each variable a scalar m//g matches (pre-scanned into `%POS_VARS`) keeps an
  i64 pos cell (-1 = undef), keyed like handle cells. The match runs on the
  slice from pos, writes pos = start + m0e on a hit or -1 on a miss, and
  captures are relative to the slice (`subj_ptr` = slice pointer).
- `pos($s)` reads the cell as a Slot (undef bit). `pos($s) = N` stores it. An
  Assign or s/// to the variable clears it.
- Producer: `pos => 'Scalar'`. Unknown made `defined pos($s)` always true
  ("d" for perl's "u").
- **A wrong answer found by a probe:** an m//g is a memory version, so the s///
  after it lists it as an input. Chalk's `_is_memory_version` did not know it,
  took it for a computed replacement, and replaced with the match's 1 ("1XbX").
- Refused: list context; a start-anchored or empty-matching pattern; a variable
  not assigned in the program (a foreach alias, whose pos is its element's) or
  changed by tr/chomp/chop/++/op-assign.
- Lesson: a node that becomes a memory version (here, newly lowered) must be
  known to `_is_memory_version`, or every operand-position heuristic misreads it.
