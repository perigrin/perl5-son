# A block eval records its join but not its entry

**Date:** 2026-09-15
**Status:** FIXED. The Region now records `eval_entry`, and the deparse uses it.

## The shape

`if (eval { ... })` lowers to a single-input Region with a Phi over it:

    16 Region in=[10]      the eval's join
    17 Phi    in=[6, 1]    the block's value, or undef if it died
    18 If     in=[16, 17]  the Phi IS the condition

The Phi's region is neither a Loop (not loop-carried) nor a two-armed branch
join, which is why the deparse's Phi rule refused it at first.

## Why the deparse cannot spell it

The Region's input is the LAST STATEMENT of the block, and nothing marks the
FIRST. Measured on
`our $g=0; our $h=0; $h=5; if (eval { $g = 1; 1 }) {...}`:

    Region(23) in=[12]
    chain back: EntryWrite 12, 11, 10, 9, Start

Four stores chain to `Start` and only the last is inside the eval. The other
three are `our $g=0`, `our $h=0` and `$h=5`, all outside it.

So the body cannot be delimited. Guessing in either direction is wrong:

  - starting too early pulls unrelated statements into the block. Measured,
    that put `die "x\n"` inside a `eval {}` that had not yet opened -- the
    emitted program DIED where perl printed `died g=1`;
  - starting too late leaves protected statements outside, so a die escapes.

A block eval's whole meaning is WHICH statements it protects, so this refuses.

## The string form is fine

`eval "..."` builds `Region[Coerce(Str->Code)]` -- the Region's input IS the
eval, a single node, needing no delimiting. That form renders and round-trips.
Both share the join shape, which is why one check recognises both and only the
body handling differs.

## The fix

`Region` gained an `eval_entry` field naming the control node the protected
body began after. The producer had it all along -- `$sim->control` at
`_handle_entertry`, before the body walk -- so recording it cost one line.

It rides the wire as a node INDEX, like `region` and `predecessors`, and is
emitted only when set, so every other Region's wire is unchanged. A string
eval leaves it unset: its Region's input IS the eval, one node, nothing to
delimit.

## The other half: claim it at the ENTRY, not the join

Recording the entry was necessary and not sufficient. The deparse first used
it while still recognising the construct when the walk ARRIVED at the Region --
and a block eval's body is ordinary chain between the two, so those statements
had already been emitted. Measured, they appeared BOTH before the `eval {` and
inside it, and a `die` among them escaped:

    $main::g = 1;
    die "x\n";              <- outside the block
    my $eval29 = eval {
      die "x\n";            <- and inside it
      1;
    };

So the eval is now recognised when the walk is standing ON its entry. The body
walk then needs a re-entrancy guard, because it starts at the very node that
identifies the construct -- without one it recognised the same eval again and
recursed forever.

WIRE CHANGE: chalk's Region needs the same field to delimit a block eval.
It is optional and absent on every other Region, so an un-updated consumer
reads existing graphs unchanged.

## Where this bites

`base/rs.t`'s `test_bad_setting` is this shape eight times over:
`if (eval { $/ = \0; 1 }) { ... } else { ... }`. The other three methods in
that file render; this one is the whole reason the file does not round-trip.
