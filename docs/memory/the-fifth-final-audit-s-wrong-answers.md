---
name: the-fifth-final-audit-s-wrong-answers
description: "Fifth final goal audit 2026-11-27 (read-only), heads 396aae40 / a2fe984d: gates hold; 2576 fresh probes (probes/v) found 301 silent wrong answers in eighteen classes Q1-Q18; `$t = \"$s$s\"` is dropped (stringify TARGMY); five classes sit on the edges of audit 4's fixes; 23 are promotion's (an index compared by spelling, V14 passes them); the verifier flags 10 of 301 and chalk's loader let those through"
metadata:
  type: project
---

Fifth final audit of the memory-model goal (2026-11-27;
docs/research/2026-11-27-memory-model-final-audit-5.md). Producer 396aae40,
chalk a2fe984d. No code changed. New probes `probes/v/` (2576): SAME 1587,
REFUSED 675, LOUD 13, **WRONG 301** (first broad round 29 of 1610, 1.8%;
rounds aimed at each wrong 272 of 966). Audit 4's X1-X7 are closed as probed.

**The classes** (report section 4; `v/_classes.tsv` names each probe's):
- Q1 (20) `my $s = "a"; $s = "$s$s"` prints `a`: before the peephole pass the
  tree is `stringify[$t]/TARGMY` over `concat`; the `stringify` handler
  (FromOptree.pm:13546) pushes a Coerce and never reads OPpTARGET_MY.
- Q6 (55) the value of a list assignment in a list (X4's fix,
  FromOptree.pm:13500): the targets' values then, not the targets; with a
  call after it a `my` target vanishes (`((($x,$y)=(7,8)), z())` is `7  0`).
- Q2-Q5 (103) the operand rule (X7's fix): `&&`/`||`/`//` re-read the left
  operand only (:26283); `($x) x 2`, a list in a `do` block or `map` body,
  `++$x` as a call argument (:6260), `substr`/`$#a` as arguments, `$1`.
- Q10 (23) promotion: `$a[-2]` against `$a[0]`. AliasProof.pm:237 and
  PromotedPrivate.pm:76 compare constant indices as strings. SAME with
  SON_NO_PROMOTE=1; V14 passes all.
- Q11 (15) `for my $i (1..3) { $i *= 2; push @r, \$i }`: X1's fix keeps the
  iterator in memory and the store only rebinds the SSA slot.
- Q8 (13) `local ${"x"}`, `local $$n`: no `local` on the wire, no GAP.
- chalk, wire right: `local %h` (Q7, 10), an :lvalue sub under local (Q9, 4),
  `(@{$h{a}}, "x")` read late (Q13, 18), `(a => f())` with f returning
  nothing (Q16, 14).
- Q12 (6) `\$a[1]` then `@a = reverse @a`; Q14 (9) `delete @h{@$k}`; Q15 (5)
  `$_ *= 2 for @a[1..$#a]`; Q18 (4) `\(my $v = 1)`; Q17 (2) singles.

**Lessons:**

- **A fix closes its probes, and the next audit finds its edge.** X4, X7, X5,
  X1 and X3 each have a class here one shape away. A fix needs the neighbours
  of its own rule probed, not the neighbours of the old bug: which operand,
  which target kind, which spelling of the same thing.
- **Two checkers written from one wrong assumption agree.** V14 is its own
  module now and still names an element by its index's spelling. Only the
  differential (`SON_NO_PROMOTE=1`) is independent, and it sees only probes.
- **B::SoN reads a tree perl never runs.** The peephole pass moves TARGMY
  from `stringify` to `concat` (Q1) and makes `reverse` in place (Q12).
  Concise shows the tree after it: debug with the walk's own trace.
- **The loader and the verifier are two rule sets.** Ten wrong wires broke
  `read-unversioned` or `record`; chalk loaded and ran them.
- **A hash printed in its own order is not a probe.** Twelve first-draft
  probes (`join(",", %h)` with two keys) had two right answers; run each
  probe several times under perl before counting it.
- **The rate does not fall.** 7 to 19 percent of fresh hand-written probes
  were wrong in each of eight audits. A probe gate measures the last audit.

Related: [[the-fourth-final-audit-s-wrong-answers]],
[[the-fourth-final-audit-s-wrong-answers-lowered-or-refused]],
[[promotion-fails-closed-and-v14-checks-by-its-own-rule]].
