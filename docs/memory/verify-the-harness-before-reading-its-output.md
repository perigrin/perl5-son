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
- (2026-11-13) Rerunning one of the 300 swap files "did not reproduce" -- the
  rerun lacked the sweep's `HOME=/home/runner PERL5_SON_LIB=/home/user/repo/lib`,
  so no producer was found and every file refused at the test's own `-x` skip
  check (`Call builtin fteexec`). Same verdict for all, plausible, wrong. Rerun
  with the sweep's exact env, and debug output from `swap-one.pl` must go to a
  file (it sends stderr to /dev/null). Faster still: save the wire once
  (`-MO=-q,SoN,json`) and replay only the load step.

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

- 2026-11-15: once chalk compiled its own implementation classes (Chalk::Impl,
  for %SIG/%INC) by running B::SoN at compile time, the census stage -- the one
  stage of verify-r.sh that did not set PERL5_SON_LIB -- turned seven
  ROUNDTRIPs into "GAP: Chalk::Impl::SIG cannot be compiled in". ROUNDTRIP read
  407, which looked like a regression. Every stage of a verify sets the same
  env; a new compile-time dependency on the producer is one more reason.

- 2026-11-16: t/bootstrap/element-memory-ssa.t failed in four verifies and was
  pushed. Two harness holes hid it. (1) The "NEW FAILS" diff is against a
  107-entry baseline from long ago that still lists this file, so a fresh
  failure of a file once red reads as "not new". The head-failure LIST is the
  measure: anything there but perl-recognize-phase5.t is a failure until shown
  otherwise. (2) The solo rerun that "passed" ran without PERL5_SON_LIB and
  HOME, and printed `Tests=0 ... NOTESTS` -- zero tests run, read as a pass. A
  solo rerun sets the same env as the suite, and NOTESTS is never a pass. (The
  failure itself was a stale expectation: T2 now lowers a shape the test
  required it to refuse, with perl's answer.)

- 2026-11-17: verify-r.sh's suite stage ran `t/bootstrap/*.t` and
  `t/bootstrap/ir/*.t` only, so 13 red files in mop/, regex/, scheduler/,
  corpus/ and t/ itself never showed, and "chalk suite 0 failures" was claimed
  over two directories. An agent found them by running the whole tree. The
  suite stage is now `find t -name '*.t'` (minus mode2-extractor.t, which needs
  ~/dev/perl5), with a 40-minute per-file limit since the own-source test takes
  17. Check the DENOMINATOR of the suite too, not only of a census.
