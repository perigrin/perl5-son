---
name: census-cause-split
description: 430/430 goal, "Call builtin split" (3) -- split on a literal, " " or //; fields are views; trailing empties dropped; 218 -> 220
metadata:
  type: project
---

**Cause:** "cannot lower op=Call builtin split" (169 170 387).

**Built (chalk 5b32295e):** _lower_split, in a list. Its inputs are
(pattern Constant regex|string, string, limit Constant 0). The loop state
lives in entry allocas (i, start, keep, in-word). Each field is a %Str
view into the string, boxed and pushed. `keep` tracks the count up to the
last non-empty field, and the array length is cut to it at the end. That
drops trailing empties and turns "" into an empty list.
- literal: a regex value with no metacharacter, compared with memcmp.
  Leading empty fields stay (`",a"` gives ("", "a")).
- " " (a STRING pattern): awk mode, the runs of non-whitespace.
- //: each byte.
- Refused: a regex, a limit other than 0, scalar context, no string.

**Result:** 218 -> 220 (170 387). 169 moved on to NumLe over an Unknown
operand (`$j <= $#chars`).
