---
name: two-tables-that-agree-can-both-be-wrong
description: "An agreement test between B::SoN's and chalk's type tables finds where they differ, never where both are wrong; settle each difference against perl, not against the other side"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-25T00:00:00.000Z
---

On 2026-11-25 the lattice and operator-table agreement tests were added in both
repos (t/lattice-agrees-with-chalk.t, t/operator-table-agrees-with-chalk.t and
chalk's t/bootstrap/ twins). The lattice differed only in reflexivity: B::SoN's
`is_subtype_of` was strict, and B/SoN.pm had an `eq` arm to undo that. The
operators differed on 16 rows. perl decided which side was wrong for each one,
and it was not always the same side. chalk was wrong on `<=>`/`cmp` (-1 is an
Int), `%` (7.5 % 2 is 1), unary `-` (-"abc" is "-abc") and wantarray. B::SoN
was wrong on the `&&`/`||`/`//` cap: List narrowed `*STDOUT || *STDERR`, which
is a GLOB.

Three shared errors pass both tests, because both tables agree on them: unary
`+` (Num in both; perl returns the operand unchanged), string `..` (Int operands
in both; `'a'..'e'`), and `=~` with `/g` in list context (Boolean in both).

**Why:** an agreement test compares the two copies. It is not an oracle for
either one.

**How to apply:** for each difference, run perl before choosing a side. When a
cross-check shows the copies agree, the facts still need their own check
against perl. Related: [[a-refusal-test-that-only-translates]], [[make-the-guard-fail-on-purpose]].
