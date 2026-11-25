---
name: the-third-final-audit-s-wrong-answers
description: "Third final goal audit 2026-11-25 (read-only), heads 76f33aa / eca706af: gates hold, verifier 0 on corpus, 3184 probes and chalk's lib; 1373 fresh probes (probes/y) found 146 silent wrong answers in twelve classes N1-N12, 101 of them one shape past a K-class fix; 30 probes break a verifier rule (9 of them wrong); the rate rose, 7% to 10.6%"
metadata:
  type: project
---

Third final audit of the memory-model goal (2026-11-25;
docs/research/2026-11-25-memory-model-final-audit-3.md). Producer 76f33aa,
chalk eca706af. No code changed. Verifier with SON_RATCHET=1: corpus 431,
probes 3184, chalk lib 221 wires, 0 violations. New probes `probes/y/`
(1373): SAME 789, REFUSED 421, LOUD 16, **WRONG 146** (10.6%; the audits
before: 59, 55, 68, 111, 57). 39 are in `y/unverified/` (30 break a
verifier rule, 9 the pre-scan agreement test).

| class | n | what | next to |
|---|---|---|---|
| N1 | 13 | a callee's `@_` copy shows a store by `tr///`, through `\$_[0]`, or made in a loop | K1 |
| N2 | 9 | `@_ = ()` not applied; `$_[0]` follows the index after `unshift @a` | new |
| N3 | 8 | a foreach/map/grep item after an EARLIER pass stored a later element | K3 |
| N4 | 18 | an element assignment's value, then a store by a call, nested element or reference | K5 |
| N5 | 16 | a slice, `values`, `reverse`, `grep`, `?:` in a list, then an element store | K7 |
| N6 | 13 | `for ($x .= "b")`, `($x = $y) = 7` | K4 |
| N7 | 11 | `$o->m($g, $g++)`; `f($g, $g =~ tr/a/z/)` | K6 |
| N8 | 10 | `local $g;` with no value, conditional `local`, `print $g, local $g = 5` | K2 |
| N9 | 22 | a followed module's file lexicals, shared refs, prints, import, INIT/CHECK | K9 |
| N10 | 5 | `my $i; for $i (...)` seen by a closure | new |
| N11 | 6 | `substr` / `$#a` as an argument or foreach item | new |
| N12 | 15 | `length(undef)`, `reverse` by context from a sub, `(1,2) x 2` scalar, split counts | new |

**Lessons:**

- **A refusal keyed on a spelling is as wide as its probes.** Each K fix
  closed its probes; the same property spelled another way (a call for an
  assignment, a slice for an array, a method call for a direct one, `tr`
  for `=`) is still wrong. Key on the property: an lvalue operand, and
  anything later that may store.
- **Three scans, three lists of storing ops.** `tr///` was missing from the
  ones that decide `@_` places and alias operands. One table.
- **The verifier fires on new wires.** 9 wrong wires and 12 right programs
  broke V6 or V12; core modules (Math::BigInt, Benchmark, Text::Balanced)
  break five rules. The zero in the ratchet is a zero on its sets.
- **A second round is where the count is.** First round 6.4%, broad 2.9%,
  the round around the hits 38%.
- **`git mv -k` on an untracked file does nothing and exits 0.** Thirty
  probes "moved" and none had. Check the destination.

Related: [[the-second-final-audit-s-wrong-answers]],
[[the-second-final-audit-s-wrong-answers-lowered-or-refused]],
[[a-refusal-keyed-on-a-constant-fixes-a-probe]].
