---
name: census-cause-bitwise
description: 430/430 goal, "cannot lower op=BitAnd" (4: 046 049 050 051) -- & | ^ lowered when perl surely does them on numbers; string bitwise and ~ refused by name; an unsigned result past i64 stops; 254 -> 256
metadata:
  type: project
---

**Cause:** "cannot lower op=BitAnd" (046 049 050 051). Refused earlier on
purpose: perl's & | ^ are numeric OR string (bytewise), decided at run time
from the operands' number flags (pp_bit_and: numeric if either is NIOKp),
and the result is a UV.

**Built (chalk 3bae0131):**
- BitAnd/BitOr/BitXor carry B::SoN's `flavor` (numeric under the bitwise
  feature; `&.` string) -- a field in the node's content hash.
- `_lower_bitop`: numeric when flavor is numeric or an operand is a numeric
  literal (a literal is surely NIOK); operands coerced to Int; and/or/xor
  i64. Anything else refused by name -- a variable's flags (a string once
  read as a number counts as one) are not on the wire.
- The UV result: a negative i64 (past IV_MAX unsigned) stops the program
  (exit 255) unless every consumer is another bitwise op. Only reachable
  with negative operands.
- `~` (Complement) refused by name: on a string operand it is bytewise.

**Result:** 046 051 round-trip; 254 -> 256. 049 (~) and 050 (two strings,
no feature) refused by name.

**Judgment call, recorded:** the exit for an unsigned result is a
run-time stop, not perl's answer -- accepted here because it needs
negative operands to a bitwise op; NOT accepted for Scalar-container stores
(autoviv), where the stop would fire on a common idiom.
