---
name: verify-the-harness-before-reading-its-output
description: A census is a program too; three of mine silently measured the wrong thing before any finding was read
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T05:36:07.535Z
---

A sweep, census or extractor is a program, and it fails the same ways the code
under test does -- silently, plausibly, and with a number attached. Verify the
harness measured what you think BEFORE reading a single finding out of it.

Three in one project, each caught only because a result looked wrong:

- `ls *.t | while read f; do perl ... "$f"; done` -- the inner perl drained the
  file list from stdin, so the loop ran once and reported 986/986 CLEAN. The
  real numbers were 857/129. See [[a-shell-loop-can-eat-its-own-input]].
- `-MO=SoN,json,package=main` FILTERS OUT every other package, so a fixture
  declaring `package Foo` lost `Foo::hi` and the emission called a method that
  did not exist. Four "defects" were my extraction; the totals moved 127/47 to
  134/42.
- "11 of 29 sampled, 18 remain" -- the done-list held 12, so 17 remained, and
  18 was also the unrelated count of the other two failure modes. Two
  populations, one number, reported for two turns.

**Why:** a harness produces a number, and a number reads as evidence. Nothing
in the output says which question was asked, so a wrong question yields a
confident answer about something else.

**How to apply:** before quoting a sweep, check three things.
1. DENOMINATOR -- does the result line count match the input count? 986 files
   must produce 986 rows.
2. FILTERS -- does any flag narrow what was measured? `package=`, `head`,
   `grep -m1`, a timeout.
3. A KNOWN CASE -- run one input whose answer you already know and confirm the
   harness reports it. A known refusal must still refuse.

And treat a SUSPICIOUSLY GOOD or suspiciously bad number as a harness bug
until proven otherwise. All three above were found that way, not by review.

Related: [[a-sweeps-absence-is-not-evidence]],
[[truncated-output-manufactures-facts]],
[[clean-counts-cannot-measure-progress]]
