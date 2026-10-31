# Census cause: qx and glob through libc (375 -> 379, pin 1e5230c1)

**Cause:** `BacktickExpr` and `Call builtin 'glob'` had no lowering.
perigrin's decision (decision-remaining-refusals.md) made them targets
through libc: popen for qx, glob(3) for glob. They held 014, 365, 366
and 370.

## What changed (chalk 1e5230c1)

- **qx / readpipe.** `_lower_backtick` NUL-terminates the command and
  calls `@chalk_qx(i8*, i64*)`. The helper flushes stdout, popens the
  command, reads into a buffer that doubles as it fills, and pcloses.
  Flushing first keeps output printed before the command in order.
  A program that reads `$?` is refused by name: `$?` isn't set yet.
- **glob.** `_lower_glob` calls `@chalk_glob(%Array*, i8*)`, which runs
  glob(3) with NOSORT|BRACE|NOMAGIC|TILDE. It then sorts with qsort
  using `@chalk_glob_cmp` (strcasecmp, then strcmp, as perl orders) and
  pushes Str slots.
  - Refused: scalar glob, a consumer that isn't a list, and a constant
    pattern with whitespace (perl splits it into several patterns).
  - A computed pattern with whitespace stops at run time.
- `llvm-unlowered-statement-ops.t` dropped its BacktickExpr case.
- Tests: llvm-a-command-run-by-qx.t (5) and llvm-a-glob-lists-files.t
  (7). Both were red on 86e91463.

**Round-tripped:** 014, 365, 366, 370.

**Seen on the way:**
- glob's elements come back untyped (Unknown stamp), so reading them
  for a typed use may refuse. Kept in the tests' "may refuse" group.
- The producer drops an unused `my $o = qx{...}` entirely, so the
  command never runs: a lost side effect. To report to perigrin.
