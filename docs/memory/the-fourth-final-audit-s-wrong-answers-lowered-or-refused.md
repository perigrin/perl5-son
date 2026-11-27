---
name: the-fourth-final-audit-s-wrong-answers-lowered-or-refused
description: "Branch x-wrongs: audit 4's X1-X4, X6, X7 (56 WRONG) and audit 3's N5 leftovers lowered or refused by name; the operand rule's two roots (an ex-pushmark list, an op handing its SV on); a glob bind of a scalar is a bound name; X5 left to the promotion fix"
metadata:
  type: project
---

Branch `x-wrongs` (2026-11-27), producer from 9edd0dc5, chalk from 07111727.
Audit 4 (docs/research/2026-11-26-memory-model-final-audit-4.md) left 72
WRONG in probes/x; X5 (16, SoN::AliasProof) went to another session.

| class | outcome | how |
|---|---|---|
| X3 (15) | REFUSED | `local` on an aslice/hslice, by name in `_local_shape_gap` |
| X1 (6) | 5 SAME, 1 REFUSED | a range enteriter's variable is renewed per pass (`_renewed_per_pass`), so the Ref carries `fresh_each_pass` and chalk's fresh_cell makes a cell per pass; chalk: an inner loop uses the enclosing pass's cell (was a cell nothing stored: `,,,`); a call's value that may alias a range iterator refused |
| X2 (6) | SAME | chalk: `EntryWrite binds` of a package scalar is a bound name (bind::NAME) set to the referent; to a literal, a read-only cell and a checked store (perl dies); in a program with an eval, a store to such a name refused (the wire gives it no way out). A local's restore is told apart by its save |
| X4 (13) | SAME | an aassign in list context to elements/slices pushes element reads at its version; other mixes or list-valued indices refused |
| X6 (2) | SAME | tr///r and s///r of a demoted slot read it at memory: the binding a destructive tr left is the Transliterate (chalk reads it as the count) |
| X7 (14) | 10 SAME, 4 REFUSED | see below |
| N5 (3) | 1 SAME, 2 REFUSED | `values %h` and a hash slice are aliases: only a hash flattened whole is limited to call effects |

Gated (chalk t/data/audit-probes): 809 x probes as x<name> (X5's 16 left out
by name) -- SAME 574, REFUSED 231, LOUD 4 -- and 94 of audit 3's 110 left-out
y probes (78 SAME, 16 REFUSED); yp13 (hash order) and ya57 (a freed scalar)
stay out as not deterministic, 14 more because their wires still break a
verifier rule. Whole sweep, 5408 probes: promotion on SAME 4035, REFUSED 1333,
LOUD 40, WRONG 0, no verdict changed; off WRONG 0, SAME lost 0.
`undef $$r` (an internal error masked as a skip) is refused by name.

**X7's root was two holes in the operand rule, not fourteen consumers.**
(1) `_operand_kids` opened an ex-list only when its first kid was a live
`pushmark`; a slice's index list starts with an ex-pushmark (a null), so the
indices were never consumer operands. (2) An op that hands its operand's SV
on (`scalar`, a one-statement `do` = `scope`) carried no note. `||` `//` `&&`
are made again as the arm perl chose (by the value then) with the SV read now;
a ?: arm, sort/grep/reverse items and an :lvalue sub's value are refused by
name where a later operand's effects conflict with their place.

**Lessons:**

- **perl copies in more places than it looks.** `do { 1; $x }` is a `leave`
  (copies), `do { $x }` a `scope` (aliases); `map { $_ } $x` copies, `grep`
  aliases. The first draft treated all four alike and lost xu93 SAME and made
  `do { 1; $x }` wrong. Probe each pass-through against perl before listing it.
- **Unpeeped trees differ from Concise's.** `scalar($x)` is a real op under
  B::SoN (Concise shows it nulled). Debug the walk with a guarded `warn` of
  each consumer's kids, not with Concise.
- **A neighbour probe finds the next hole.** X1's fix exposed a chalk
  fresh_cell bug (an inner loop referring to the outer pass's `my`: `,,,`),
  older than X1. And a body `my` handed to a sub that returns or keeps
  `\$_[0]` kept one slot for every pass (`3,3,3` for `1,2,3`): lowered on
  branch loop-my-fresh: a place argument of a pad scalar renewed on a cycle
  through the call carries fresh_each_pass (as a Ref does), and chalk gives
  it a cell per pass -- named sub, method, code ref (xm24-xm33 SAME). The
  refusal it replaced, asked of every method, had cost 11 deparse files and
  4 corpus graphs; the lowering cost none. Its neighbour `for my $x (@a) { f($x) }` with f
  storing `$a[0]` before reading `$_[0]` printed 1 for 5 (xm27): chalk made
  f take its argument by value because the iterator aliased by reference is
  no place --  as aliases now, but not for a foreach over @_ (a caller's
  literal there stops an alias at run time: two chalk tests caught it).
- **A literal bound by a glob is read-only.** Binding `*x = \42` to a plain
  cell made `$x++` succeed where perl dies; and in an eval the run-time die
  only sets a flag the wire gives no branch for -- refuse, do not lower.
- **The suite caught the new rule past its class, the probes did not.**
  `my $v = $x || g()` was refused: g() in the logop's own right arm counted
  as "stored since" (that arm runs only where the value is its own -- ask
  about later operands, not the chain); a plain call in a ?: arm was taken
  as an alias (a copy; only an :lvalue sub's is). 7 files and 1 corpus graph.
- **A baseline's reasons can be older than its producer.** Re-recording
  changed ~60 reasons; all but one were the same under the base producer.
  Check a changed reason against the base before blaming the branch.
- **xt24 was a verifier precision gap**, not a dropped store: a closure's
  CellParam is the cell, as the maker's MakeCell is (V13).
