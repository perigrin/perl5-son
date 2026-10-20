---
name: perl-t-coverage-2026-08-30
description: Measured B::SoN coverage of perl's t/ as of 2026-08-30 -- 98 of 548 files
metadata:
  type: project
---

Measured 2026-08-30 (commit 3afe1fc). perl's `t/` holds **620 files**; 548
measured, **98 translate clean (18%)**.

    dir        total   ok    gap   crash
    base           9    7      2       0
    mro           73   46     27       0
    re            80   23     57       0
    op           227   11    215       1
    comp          25    4     18       3
    io            44    2     42       0
    run           28    2     26       0
    cmd            5    1      4       0
    lib           10    1      9       0
    opbasic        5    1      4       0
    class         12    0     12       0
    uni           30    0     30       0

Unmeasured: bigmem, porting, win32, perf, benchmark, japh, test_pl (72).

**MEASUREMENT TRAP — perl's tests use relative `require ./test.pl`, so the
survey must `cd` to `t/` first.** Running from elsewhere reports ~96 phantom
"crashes" that are just `Can't locate ./test.pl`. I nearly reported class/ and
uni/ as 100% producer crashes on that basis.

Where the leverage is: `op` is 227 files (41% of measured) with 11 passing —
biggest lever, also hardest. `class` (0/12) and `uni` (0/30) are clean sweeps
of GAPs, so a single blocker may gate each whole directory.

Only 4 real crashes across 548 files, 3 of them in `comp`.

Related: [[tbase-coverage-is-the-producer-corpus]], [[crashes-mask-gaps]]
