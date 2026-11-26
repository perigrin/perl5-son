---
name: interval-oracle-drift-is-a-wire-diff
description: When chalk's integer-intervals oracle test loses/gains rows, diff answers under base vs new producer with the same chalk first; a rename shows as one LOST + one NEW
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-26T12:00:00Z
---

t1-integer-intervals-prove-nothing-new.t keys rows by structural node id, so
a wire change renames proofs: places-everywhere made Length Maybe[Int] (no
Coerce Scalar->Str on its operand) and `my (...) = @_` a Subscript by
Constant index. Each showed as LOST `Length|Coerce|...` plus NEW
`Length|Subscript|...` (gaps:30, 65, 149), plus new Constant 0/1 rows
(111-113, 145, 149). A grep of the NEW list for only some cases missed half.

**Why:** "lost and nothing gained" was a misread; the full NEW list had the
renamed row. Same chalk + base producer (git archive b8dceb11 lib) vs new
producer isolates the cause in one diff.

**How to apply:** pipe each case's wire through the test's answers() walk
under both producers; re-record only the drifted cases' node rows (keep
case lines), check two PERL_HASH_SEEDs. Note: chalk's loader drops the
wire's Maybe[Int] and TypeInference stamps Length Int, so the analysis
proves iv for length(undef) too; T2 still printed perl's answer (probed).

Related: [[an-analysis-rewrite-is-held-to-its-old-answers]]

## A fact held in three places (chalk dfe8144e)

When B::SoN made `length` Maybe[Int], chalk's operator-table test caught it,
but chalk held "length is Int of a Str" in three places: TypeLibrary,
Analysis.pm's fixed stamp rule, and TypedInvariant's operand check. Changing
the table alone was not enough. The interval oracle lost 8 Length proofs
(LOST allowance 9 -> 17): each was an iv proof for a length whose operand may
be undef, unsound. Removing an unsound proof raises LOST; that is the right
direction. Open: B::SoN stamps `$ENV{KEY}` reads Str though they may be undef.
