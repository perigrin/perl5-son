# A block eval records its join but not its entry

**Date:** 2026-09-15
**Status:** REFUSES in the deparse. The fix is producer-side and scoped below.

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

The producer should record the eval's ENTRY, not only its join. The optree has
it: `entertry` is the op, and its position in the exec chain is exactly the
boundary. Either a CFG node at the entry (mirroring the Region at the exit) or
a field on the Region naming the first protected node would do.

Note the try/catch path already builds both sides (`_walk_branch` over the try
body, then a merge), so the machinery exists -- a plain block eval simply does
not use it.

## Where this bites

`base/rs.t`'s `test_bad_setting` is this shape eight times over:
`if (eval { $/ = \0; 1 }) { ... } else { ... }`. The other three methods in
that file render; this one is the whole reason the file does not round-trip.
