# Plan: Test::Chalk, chalk's tests as programs compiled through LLVM (perigrin, 2026-10-31)

**Goal.** An oracle like perl.git's `t/`: compile chalk's own tests as
programs through B::SoN -> chalk's LLVM backend -> `lli`, and compare
their TAP with perl's.

## Test::Chalk

- **What it is.** The subset of Test::More that chalk's tests use,
  written in perl that compiles cleanly through LLVM. That is the proof
  required: chalk's Perl target or gate 3 does not count.
- **The swap.** Each test changes one line, `use Test::More` to
  `use Test::Chalk`.
- **Usage measured** (559 Test::More files, 43 Test2::V0 files):
  - easy (ok, is, isnt, pass, fail, diag, note, plan, done_testing,
    BAIL_OUT): 215 files use only these;
  - medium (skip, isa_ok, can_ok, cmp_ok): 269 with these;
  - hard (`like`/`unlike`: runtime regex; `subtest`: code refs as values;
    `is_deeply`: recursion over refs): the rest.
- **How it grows.** One function at a time. A function goes in only
  once a probe program that uses it round-trips through LLVM.

## Producer blockers (first step)

Seen on probe tc1 (`use Test::Chalk; ok(...)`).

- **Used modules are invisible.** `_cv_is_user_code` counts only subs
  compiled from the program's own file. A `with=MODULE` option must
  include named modules; later `with=Chalk::*` for the census.
- **Imported aliases don't resolve.** `main::ok` is an alias created at
  import. The call must name the CV's real home, `Test::Chalk::ok`.

## Requirement for later: chalk's own parser must parse Test::Chalk

When work returns to full chalk end to end (chalk's own parser, not
B::SoN), that parser must parse Test::Chalk and the converted tests.
Keep Test::Chalk to syntax chalk's grammar covers, and check it there
when that path is live.

**Order:** finish the qx/glob pin, then the producer `with=` and alias
resolution, then Test::Chalk function by function, then the 559-file
swap, then the chalk-t-through-LLVM census.

## Checking Test::Chalk against Test::More's own tests (perigrin: do this too)

Test-Simple's suite is in the perl checkout's git (`/home/perigrin/dev/perl5`,
not checked out): 394 files under `cpan/Test-Simple/t`. Read them with
`git show HEAD:<path>`.

- **The 29 public-API tests.** Of the 127 Legacy tests, 29 use only the
  public API. Run them with a shim that maps Test::More to Test::Chalk;
  each must pass as it does under Test::More.
- **A differential harness for the rest.** The other ~98 test through
  internals (Test::Builder, Test::Builder::Tester `test_out`/`test_err`,
  Test2). Lift their inputs and expected output into a harness that runs
  the same calls under both modules and compares stdout (the TAP)
  exactly, and stderr (failure diagnostics) too.
- **The swap.** Every converted chalk test must print identical TAP
  under Test::More and under Test::Chalk.
