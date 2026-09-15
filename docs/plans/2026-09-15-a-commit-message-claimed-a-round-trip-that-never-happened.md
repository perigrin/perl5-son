# A commit message claimed a round-trip that never happened

`e1d9963` ("an op name is not always the Perl spelling") says:

> comp/filter_exception.t and comp/require.t move DIFFERS -> ROUND-TRIPS.

Both claims are false. Checked out at that exact commit in a worktree and
measured:

    comp/filter_exception.t    DIFFERS
    comp/require.t             GAP

The same commit's claim about `base/lex.t` (DIFFERS -> GAP on `trans`) IS
correct, as is the suite count.

## How it happened

The corpus sweep that produced those two lines was started BEFORE the
`dofile` spelling was added and finished after. Its output was read as
though it described the committed state. Two files that had been refusing
on `dofile` appeared in the listing without a GAP line, and absence was
read as success.

**This is the second time in one session.** `base/lex.t` was twice
reported as ROUND-TRIPS on the same reasoning -- it had dropped off a
sweep listing because the per-file timeout killed it, and the missing
line was read as a pass. Corrected both times on re-measurement.

## The rule

A sweep's output describes the tree as it was when that file ran, not
when the sweep finished. Before quoting a sweep in a commit message,
either

  - start it after the last edit and let it finish, or
  - re-measure the specific files being claimed.

And a file's ABSENCE from a listing is never evidence of anything: a
timeout, a crash, and a pass all look identical.

## Also worth recording

`comp/line_debug.t` has DIFFERed since `dofile` gained its spelling, and
that is EXPECTED rather than a regression: the emitted program now
actually runs `do "comp/line_debug_0.aux"`, which fails because `.` left
@INC in 5.26. Before the spelling it called an undefined sub and failed
differently. The file also exercises `$^P` and the `_<FILE` debugger
globs, which the graph does not model at all -- the emitted program
compares a string to a number where perl compares glob contents.
