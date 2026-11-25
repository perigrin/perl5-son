---
name: the-second-final-audit-s-wrong-answers
description: "Second final goal audit 2026-11-25 (read-only), heads 888d71b / f1d9aa74: gates hold, the last audit's caveats closed but four small ones; 828 fresh probes (probes/z) found 57 silent wrong answers in nine classes K1-K9, all with clean wires; the fast path's proof for iterators and @_ copies, lvalue results read as values, local under an alias, a pre-scan miss not refused, module initialisers"
metadata:
  type: project
---

Second final audit of the memory-model goal (2026-11-25;
docs/research/2026-11-25-memory-model-final-audit-2.md). Producer 888d71b,
chalk f1d9aa74. No code changed. Gated probes 2351: SAME 1860 REFUSED 476
LOUD 15 WRONG 0. Verifier: corpus and the 2356 older probes, 0 violations.
New probes `probes/z/` (828): SAME 540, REFUSED 224, LOUD 7, **WRONG 57**
(7%; the audits before: 59, 55, 68, 111).

| class | n | what | side |
|---|---|---|---|
| K1 | 13 | a callee's `my (...) = @_` read after a store through `$_[N]` | the copy is a record over ArgsSource, no version |
| K2 | 5 | `local` of a variable an alias reaches | model: local is a store to the same place |
| K3 | 5 | a foreach/map/grep item read after a call that stores its array | producer: per-pass Subscript at the header's memory; V12's list half was never built |
| K4 | 8 | an lvalue with no rule (`?: x=`, `($x = $x+1) *= $x`, `inc($x .= "b")`, `for ($x += 5)`) | producer: store dropped, no GAP |
| K5 | 6 | `($a[0] = 5) + ($a[0] = 7)`, `++$a[0] + ++$a[0]` | producer: the element GAP's scalar twin exists, not this one |
| K6 | 2 | `f($g, $g++)` | chalk: the wire is right, the old read is made late |
| K7 | 3 | `my @b = (@a, $a[0] = 9)` | producer: the literal flattened to constants |
| K8 | 4 | `for my $x (@a) { ($x,$y) = ($y,$x) }` | producer: the pre-scan sees no write, nothing refuses |
| K9 | 11 | `use ZUp; print $ZUp::n` (module says `our $n = 1`) | producer: a followed module's file-level code is not on the wire |

Clean: rethrow edges and `local` (80), references (40), copies (89 of 90
not wrong), recursion, integer overflow and number formats (90).

**Lessons:**

- **Probe where a mechanism stops, not where it was aimed.** The 80 probes
  aimed at rethrow edges found nothing. The second round, written around
  each first-round WRONG, found 43 of the 57: eleven first hits sized into
  nine classes.
- **A fast path with three counters needs three proofs.** `call` got V12
  and "an unknown call proves nothing". `iter` and `list` did not: the
  per-pass read still names the header's memory across a call (K3).
- **A GAP written for the scalar case is a class half closed.** "A scalar
  operand is read by alias and a later operand stores it" refuses
  `($x += 1) + ($x += 1)`; the element form prints 5 for 6 (K5).
- **`git mv` on an untracked file does nothing and exits 0.** Renaming
  fresh probes needs plain `mv`; check with `ls`.
- **Run new probes from their own directory** with absolute `-I` paths:
  `use lib 'zlib'` resolves, and `AuditProbe::run_all` does not care
  about the cwd.
- **A lower-case module is refused whole** ("a direct call with no sub"),
  so "an unscanned package's scalars count as written" has no probe that
  runs end to end; only the producer's own test covers it.

Related: [[the-final-audit-s-wrong-answers]],
[[the-final-audit-s-wrong-answers-lowered-or-refused]],
[[aliases-are-places]], [[a-sub-is-walked-once]],
[[a-silent-drop-is-worse-than-a-refusal]].
