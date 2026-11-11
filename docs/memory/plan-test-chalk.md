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
  compiled from the program's own file.
  - **Fix (perigrin):** B::SoN follows `use`/`require` as other languages
    follow imports (Go, Rust, Julia). By the time B::SoN walks, perl has
    run every `use` and every literal `require`, so `%INC` names the
    files. Include every sub from those files, transitively, and list the
    modules included in the wire.
  - **The boundary is the standard library.** Pragmas are switches, not
    code. XS modules (Scalar::Util, List::Util, POSIX) are C, so chalk's
    runtime provides them, as libc provides print. Pure-perl modules are
    compiled like the program; the hard ones (Carp's `caller`, Exporter's
    glob assignment) are refused by name or replaced by a chalk-provided
    version, which is what Test::Chalk is for Test::More.
  - **`require $name` at run time** cannot be followed: a known GAP, the
    same class as run-time string eval.
  - This replaces the earlier `with=MODULE` idea.
- **Imported aliases don't resolve.** `main::ok` is an alias created at
  import. The call must name the CV's real home, `Test::Chalk::ok`.

## Requirement for later: chalk's own parser must parse Test::Chalk

When work returns to full chalk end to end (chalk's own parser, not
B::SoN), that parser must parse Test::Chalk and the converted tests.
Keep Test::Chalk to syntax chalk's grammar covers, and check it there
when that path is live.

**Order:** finish the qx/glob pin, then the producer following use/require plus alias
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

## Progress (2026-11-11, milestone 2 goal)

- **Harness:** chalk `t/lib/Chalk/CodeGen/Harness/TapDiff.pm` (modulino):
  perl vs B::SoN+T2+lli, stdout + stderr + exit byte for byte; only the T2
  path counts (a fallback is REFUSED with T2's reason).
- **Easy tier done:** `t/lib/Test/Chalk.pm` -- ok is isnt pass fail diag note
  plan done_testing BAIL_OUT, proved against Test::More's own bytes
  (`t/bootstrap/ir/test-chalk-gives-test-more-s-tap.t`, under prove and not).
- **What it took in T2:** print STDOUT/STDERR by name, exit, caller (a frame
  stack pushed around each call when the program reads caller; caller(N) only
  where at most 3 values are read), a general list assign, a pinned ternary,
  substr (perl's offset rules; outside the string stops, exit 255, as the
  fallback does) and index, a sub ended by exit/die.
- **Producer bugs found:** caller(N) dropped its N (fixed arity 0); exit's
  status under a null op (a ternary, //) dropped -- exit 0 for 2 (both now
  OPf_KIDS, as localtime). Every sub call now carries file/line/package.
- **Rules learned:**
  - A module's top-level code runs at compile time, never in the program:
    Test::Chalk keeps no initialised state, and `use Test::Chalk tests => N`
    cannot print its plan (named gap; use `plan(tests => N)`).
  - No END: done_testing prints the "Looks like you failed" summary; a plan
    with failures and no done_testing gives none (named gap).
  - Under a harness Test::More puts "\n" on STDERR before "#   Failed test".
  - `while (1) { ... return }` is a producer GAP ("loop without a lowerable
    condition"); Test::Chalk loops on a condition instead.
  - A T2 that fails to compile makes every program "T2 not tried" -- check
    `perl -c lib/Chalk/Target/LLVM/T2.pm` when everything falls back at once.
  - The .ll must not contain "Perl_" anywhere, comments included (libperl-free tests).
- Side effect: corpus T2 gate-green 196 -> 202.
- **Medium tier done:** isa_ok, can_ok, cmp_ok byte for byte with Test::More.
  `skip` is a NAMED GAP: it leaves its caller's SKIP block (`last SKIP`
  inside the sub). The producer used to DROP a loop control with no loop of
  its sub open (the skipped tests ran); it now refuses it, and the refusal
  reaches the program through `refused`. (A same-sub `last SKIP if C` in a
  bare block is also a GAP today: a loop control in a branch arm.)
- **Hard tier:** is_deeply and subtest byte for byte. Three PRODUCER WRONG
  ANSWERS found on the way, all pre-existing:
  - a package scalar passed to a sub (OPf_MOD: an alias) was taken for a
    store target and read with no version -- `w(); r($G); w(); r($G)` read $G
    once (_is_sub_argument);
  - `$G = $x . "ab"` stored `$G . "ab"`: a stacked plain multiconcat pushes
    its destination LAST (on top), an APPEND's first; it is popped first now;
  - writes in a followed module's subs were not in _package_scalars_written
    (FILE ne $0), so its package reads could forward a stale binding.
- **T2 limits met (Test::Chalk written around them, plainly):** a read through
  a reference whose value feeds a ?: and waits across a call is refused (a
  read in a ?: arm and one before it look alike in the graph); an early return
  from inside a loop body ("an if whose arms do not meet"); `foreach` aliasing
  (a Ref to the list element). Test::Chalk reads through references in tiny
  helpers and loops on a condition with a flag.
- like/unlike: T2 has no regex engine (no RegexMatch/Match at all): NAMED GAP.
