---
name: the-fourth-final-audit-s-wrong-answers
description: "Fourth final goal audit 2026-11-26 (read-only), heads 7656d8ef / 07111727: gates hold (sweep 3383/1086/36/0); 825 fresh probes (probes/x) found 72 silent wrong answers in seven classes X1-X7; 16 are SoN::Promote's (SAME with SON_NO_PROMOTE=1, V14 passes them); 110 audit-3 probes still out of the gate, 3 still wrong"
metadata:
  type: project
---

Fourth final audit of the memory-model goal (2026-11-26;
docs/research/2026-11-26-memory-model-final-audit-4.md), after "places
everywhere". Producer 7656d8ef, chalk 07111727. No code changed. New probes
`probes/x/` (825): SAME 531, REFUSED 218, LOUD 4, **WRONG 72** (first broad
round 7 of 512, 1.4%; rounds aimed at each wrong 65 of 313).

**The classes** (report section 4):
- X5 (16) promotion: `sub f { $_[1]->(); $_[0] } my $x=1; print f($x, sub { $x=5 })`
  prints 1. `SoN::AliasProof::conflict`: line 220 takes a `my` scalar as
  beyond unseen code unless a `Ref` names it (a capture is no `Ref`); line 233
  spells `my:` where the source is `my|G|$x`; the table ends `return 0`.
- X3 (15) `local @g[0,1] = ...` / `local @h{...}`: no `local`, save or restore
  on the wire; no refusal.
- X7 (14) an SV operand read before a later call stores it: slice indices,
  `substr` args, `scalar($x)`, `do { $x }`, `$x || 0`, `$x // 9`, sort / grep /
  reverse / lvalue-sub results in a list.
- X4 (13) `my ($x,$y) = @a[0,1] = (8,9)`: the record binds the inner Assign
  as one scalar (chalk: its count).
- X1 (6) `for my $i (1..3) { push @r, \$i }`: one slot for every pass; the
  refusal for `\$i` covers list foreach only.
- X2 (6) `*x = \42`, `*x = \$a[1]`: `EntryWrite binds` lowered as a store of
  the reference.
- X6 (2) `tr///r` after a `tr` on the same variable: the input is the earlier
  `Transliterate`, which chalk reads as its count.

**Lessons:**

- **A verifier that shares the pass's predicate checks the wire, not the
  proof.** V14 passed all 16. The independent check is the differential:
  `SON_NO_PROMOTE=1` on each wire with a `promoted` node (69 here) separated
  them in one run. Gate it.
- **A proof table must end "may conflict".** An unlisted source kind fell
  through to "no conflict".
- **Probes left out of a gate stay out.** BASELINE.tsv's comment lists 110
  audit-3 probes "to come in when the decision is made"; they did not. 105
  are SAME or REFUSED; `yc147`, `yp100`, `yp114` (N5, hash forms) are still
  wrong. A gate count says nothing about what its header excludes.
- **"Naive and always correct" needs its own probes.** 56 of the 72 are wrong
  with promotion off too: construction still drops (`local` on a slice) and
  still lists consumers by spelling (the operand rule).
- **An in-place perl one-liner that reads another file through `@ARGV`
  empties both.** `perl -0pi -e '... local @ARGV = "other"; <> ...' file`
  truncated the report and the table file. Read with `open`.

Related: [[places-everywhere]], [[the-third-final-audit-s-wrong-answers]],
[[a-verifier-that-reads-a-derived-flag-checks-itself]].
