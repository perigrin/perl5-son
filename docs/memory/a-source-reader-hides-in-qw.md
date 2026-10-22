---
name: a-source-reader-hides-in-qw
description: chalk-gate3's reads_source regex needs a quote before `lib/Chalk/...pm`; tests listing paths in `qw(...)` read source but count among the 488
metadata:
  type: project
---

`tools/chalk-gate3.pl` `reads_source` matches `['"]lib/Chalk...\.pm`.
Six tests name their paths unquoted in `qw(...)` or after
`$repo_root/`. They open lib/ files and grep the text:
llvm-method-abi-refinement, llvm-repr-machine-type-seam,
slot-indices-are-named, is-narrowed-guards, no-repr-names-at-t1 and
c-end-to-end. With every module overlaid they differ because the
emitted text differs, not the program.

The 488 count comes from this regex. Widening it is perigrin's call,
because it changes the goal's denominator, so it was left as is and
reported.

**How to apply:** before chasing a REAL diff, grep the test for `lib/`
in any form. `t/lib/Chalk/...` is a test helper, not lib/.
