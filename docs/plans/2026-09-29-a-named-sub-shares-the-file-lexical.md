# A named sub shares the file lexical it reads

**Date:** 2026-09-29
**Status:** DESIGN, for perigrin's approval before any code (asked 2026-09-29).

## The defect

    my $x = 5;
    sub get { $x }
    print get(), "\n";          perl 5      emitted: nothing

Five tier-1 cases stand on it: 199, 200, 201 (a named sub reads a file
`my`), 005 and 087 (the same, with `state`). Two things go wrong, measured:

  1. MAIN FOLDS THE VARIABLE AWAY. Nothing in the program graph reads `$x`
     by name -- `get()` is an opaque call -- so `my $x = 5` is a value
     binding with no reader and never reaches the wire.
  2. THE SUB'S READ BINDS TO NOTHING. `get`'s graph holds `PadAccess(x)`
     with no input; the emission spells it `$x`, and at the point the sub is
     emitted -- above the program body -- no `$x` is in scope.

Writes fail the same way from the other side (`sub bump { $count++ }`): the
sub's store is an SSA rebind inside its own graph, and main never sees it.

## What perl records (measured)

A named sub's pad marks each captured name `PADNAMEf_OUTER`, and
`PARENT_PAD_INDEX` is the enclosing CV's slot:

    my $x = 5; my @l = (1,2); sub get { $x + $l[0] }

    sub pad 1 $x   flags=0x1000001 outer=1 parent_idx=1
    sub pad 2 @l   flags=0x1000001 outer=1 parent_idx=2
    main pad 1 $x
    main pad 2 @l

So which main slots a named sub shares is a fact on the optree, not an
inference -- the same standing `_anoncode_capture_info` has for anon subs.

## The design

TREAT A SHARED SLOT AS A LOCATION, ON BOTH SIDES -- the demotion `\$x`
already gets, and for the same reason: another piece of code reads and
writes it, so its value cannot ride on a value binding.

  - PRODUCER, MAIN. Before walking the program, collect every main pad slot
    that some named user sub in this file captures (PADNAMEf_OUTER, outside
    CV = main_cv, PARENT_PAD_INDEX) and add it to `_address_taken`. Its
    declaration then becomes an ordered store, its reads carry memory, and
    it reaches the wire whether or not main reads it.
  - PRODUCER, THE SUB. The same slots, in the sub's own pad, are demoted in
    the sub's walk: a read is a memory-carrying `PadAccess`, a write an
    `Assign` store on the chain -- not a rebind the caller never sees.
  - A CALL TO SUCH A SUB IS A MEMORY BARRIER in main, so a read after
    `bump()` is a later version than a read before it. The machinery exists
    for cells (a call is a barrier once a written cell exists); extended to
    "a named sub this file defines writes a shared slot".
  - RENDERER. A shared slot's declaration is hoisted above every sub
    (`my $x;`, the pass `_emit_cell_declarations` already runs for anon-sub
    cells), and main's store becomes a plain assignment (`$x = 5;`) -- a
    second `my` would shadow it and the sub would see the outer one.

NO NEW WIRE VOCABULARY. Everything above is existing kinds -- `PadAccess`
with a memory input, `Assign` -- plus a renderer placement rule. The chalk
side sees what it sees for `\$x` today.

## Why not anon-sub cells (MakeCell / CellParam)

Cells exist because an anon sub is a VALUE that closes over the slot at the
moment it is created, and each creation may capture a fresh one. A named sub
is created once, at compile time, and closes over the one file-level slot
for the life of the program -- there is nothing per-instance to pass. A cell
would add an indirection chalk must lower for no semantic difference.

## `state` (005, 087)

At file scope a `state` variable initialises once -- which, run once, is
what `my` does -- so the main-program case is the `my` case, provided the
producer stops treating the `state` introduction as unhandled. A `state`
inside a named sub that is CALLED REPEATEDLY is different (it persists
across calls) and is not in the corpus; it is out of this design and would
refuse by name.

## Tests, before code

Round trips for: a read (199's `slot`), a write through the sub (`bump`),
an array and an element (201's `@l`), a coderef in a file lexical called
from a sub (200's `$show`), a sub defined BEFORE the `my` it reads (perl
binds it at compile time; the hoisted declaration must still precede the
sub), and `state` at file scope and in a bare block (005, 087).

## Acceptance

Corpus 005, 087, 199, 200, 201 round-trip; full suite passes; tier 2
per-file status unchanged; no tier-1 case changes bucket otherwise.
