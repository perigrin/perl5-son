# cmd/for.t: measured, parked before a fix

**Date:** 2026-09-22
**Status:** PARKED. Investigation only, no code written. Waiting on wider
corpora (pvm's graded conformance corpus, and the PerlOnJava test suite)
to rank this against everything else still refused.

## Why parked rather than finished

Fixing this moves the corpus 15 -> 14. That is one number from a 39-file
corpus whose composition nobody chose deliberately -- it is "the perl test
files that happen to be in t/base, t/comp and t/cmd". A wider corpus tells
us whether an unstamped element read on a back edge is common or a
curiosity, and that ranking should come before the fix rather than after.

[[clean-counts-cannot-measure-progress]] is the same caution from the other
side: a GAP count is a first-failure report, so moving one file says little
about how much of perl we actually translate.

## What is measured

TWO refusals, not one. The corpus census reports the deparser's
`no main::__PROGRAM__`, which is downstream of the second:

    B::SoN: skipped main::foo: GAP: function exit inside a loop body
    B::SoN: skipped main::__PROGRAM__: GAP: loop-carried value loses its
            stamp (unstamped back-edge); fixpoint restamping not yet lowered

The second is the one this file is about. Instrumented at the refusal site
(FromOptree.pm:8214) and measured on the real file:

    phi=Phi/Int  post=Add/Unknown  inputs=[EntryDef/Unknown($), Subscript/Unknown]

which is exactly what the earlier note predicted. `_deferred_backedge_floor`
requires EVERY unstamped input to be an `EntryDef` with a sigil floor;
`Subscript` is not one, so it declines and the refusal stands.

## Two facts established, both worth keeping

### 1. `Scalar` is the honest floor for a scalar element read

Measured -- a scalar element read can yield undef (missing key, past-end
index), a reference, or a string:

    my %h;  $h{x}         -> undef
    my @a=(1); $a[9]      -> undef
    $h{r}=[1]; ref($h{r}) -> ARRAY
    $h{s}="str"           -> str

And the lattice agrees that nothing narrower covers it:

    join(Undef, Str, Ref, Int, Num, Boolean, DualVar) = Scalar

So a `Subscript` floor would be `Scalar`, by the same argument `$` gets one.

### 2. A SIBLING PREDICATE ALREADY ACCEPTS THIS SHAPE

`_backedge_is_phi_recurrence` (FromOptree.pm:7963) permits an unstamped
input when it is a `Subscript`, with the comment:

    An unstamped input is acceptable ONLY if it is a deferred element
    read the loader will type.

`_deferred_backedge_floor`, a few lines above it, refuses the same shape.
WHY THE TWO DISAGREE IS UNRESOLVED -- either there is a reason worth
knowing, or the second is missing a case the first has. Reading the refusal
site to settle that is where this investigation stopped.

Do not assume it is simply a missing case. The predicates answer different
questions (one asks "is this a recurrence", the other "what floor can I
prove"), and this file has twice punished a plausible-looking shortcut.

## A dead end, recorded so it is not repeated

BISECTION DOES NOT LOCALISE THIS. The refusal needs the whole file:

    lines 1-104 + the for block at 105-109    refuses
    the for block alone                        translates
    lines 101-104 + the block                  translates
    lines 89-102 + the block                   translates
    `delete $h{foo} for $h{foo}, 1` alone      translates

Truncating at 105 is clean and at 109 refuses, which points at the
`for ("${\''}")` block -- but that block needs context from earlier in the
file that none of the slices above reproduce. Instrumenting the refusal site
found the shape in one run; bisecting spent six and found nothing.

## If picked up again

Start at FromOptree.pm:8214 and read how `_backedge_is_phi_recurrence` and
`_deferred_backedge_floor` are each consulted. Settle why one trusts a
`Subscript` and the other does not BEFORE changing either.

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
