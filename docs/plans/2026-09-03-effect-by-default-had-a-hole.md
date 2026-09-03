# Effect-by-default had a hole on the producer side

**Date:** 2026-09-03
**Status:** Fixed (commit 8254013). Recorded so the next reader knows this
was a hole in an existing decision, not a new one.
**Relates to:** chalk `docs/postmortems/2026-08-03-effect-chain-fix.md` (R1.0),
chalk `docs/plans/2026-05-22-phase-3d-effect-chain-completion.md`

## What R1.0 decided

The effect-chain-fix milestone (2026-08-03) shipped **effect-by-default Call
classification**: every `Call` unconditionally pins its `control_in`, void or
not. That was the conclusion after a world-token effect IR was designed
(2026-08-02) and killed a day later by two reviews from opposite directions --
unsound (it let sibling branch arms share an incoming world, so two identical
`Print`s hash-cons to one node, which is corpus case D1e's shape) and
unnecessary (all four live miscompiles closed in ~20 lines; the token closed
one of them).

The load-bearing finding there was **arity is not ordering**:
`Print(w0)->w1; Unwind(w0)` has perfect world arity and IS the F1 miscompile,
so the validator the design proposed could not see the bug the design was
built to prevent.

## The hole

B::SoN's generic OpMap dispatch did NOT implement effect-by-default. It pinned
a Call on control only when `OPf_WANT_VOID`:

    my $void      = ($op->flags & 3) == 1;
    my $effectful = !$opmap->is_pure($name) || $lvalue;
    $void_effect_call = $void && $effectful;

Perl does not compile every discarded result as void. `require Foo;` is
want=SCALAR even though nothing reads it, so the gate was false, nothing
threaded the node, and DCE deleted it. Measured:

    require Exporter; my $x = 1; print $x;
      graph: Start, Constant, Print, Return     -- no require, no diagnostic

`print` escaped only because it has its own node type in
`%STATEMENT_EFFECT_OPS`. Every global-state op mapped to a GENERIC Call was
exposed. The op was in the OpMap, correctly marked impure, mapped to Call --
and none of that mattered without a control edge.

## Why it matters beyond the one op

The graph said `require Foo; Foo->new` calls a method on a package nothing
ever loaded. Not a missing optimization -- a graph asserting something false,
which is the silent-drop class the refuse-or-lower contract exists to prevent.

## What was done

Scoped to global-state ops (`require`, `dofile`) rather than to impurity in
general, and the distinction matters. "Impure" in the OpMap is opt-OUT, so it
holds two unlike things:

  - real effects: `print`, `open`, `system`, `push`, `require`
  - not-yet-classified: `sort`, `split`, `length` are conservatively impure
    even though `length("abc")` is plainly a function of its input

Widening the gate to all impure ops would newly pin `length`, which costs a
real optimization for no defect in evidence. See `%GLOBAL_STATE_BUILTIN` in
`lib/SoN/FromOptree.pm`.

These ops advance MEMORY as well as control, because `use X LIST` is exactly
`BEGIN { require X; X->import(LIST) }` -- verified, the two compile to
byte-identical exec chains -- so in the runtime spelling the import must not
float above the require.

## What is NOT decided here, and must not be reopened casually

**The control/effect split is deferred behind GCM.** The 2026-07-19 chalk
conversation named the re-architecture: the current chain conflates control
(total order over all statements, which over-constrains -- pure ops cannot
float) with effect-threading (partial order over world-touching ops only).
That is the textbook SoN shape and chalk half-implements it today.

It is deferred with a named trigger: **not revisited until GCM (Global Code
Motion) is designed, Phase 9.** The reasoning is that retrofitting an IR under
a working optimizer is worse than building the optimizer on the right IR. Do
not open GCM without re-reading the 2026-08-03 postmortem first.

This commit does not touch that. It makes the producer obey a rule the
consumer already shipped.

## `use` is not a timing problem to model

It is tempting to treat `use` as a gap because it leaves nothing in the
optree: it ran in BEGIN before B::SoN was invoked, so a `use POSIX qw(floor)`
program and its runtime `require`+`import` equivalent produce radically
different graphs for the same semantics.

That framing was already ruled on (chalk, 2026-04-20, MOP/D3 scope). Phasers
are ADJUST-only; BEGIN/INIT/CHECK/END are deliberately unimplemented because
they "don't make as much sense in a closed-world environment," and if
revisited, BEGIN would run at PROGRAM ENTRY rather than parse time -- a CFG
placement directive, not a parse-time hook.

In a closed-world AOT compiler there is no parse-time to hook, so `use` is not
a timing question. It is a load that either happens at program entry or is
resolved statically, and neither needs a node.

## Open, and not owned here

The **2026-07-19 reconnaissance** -- dispatched read-only to map the current
effect model, its blast radius, and whether a World token is an EXTENSION or a
SPLIT of existing infrastructure -- has no recorded results. It may have been
lost when that session ended. If the control/effect split is to be taken up at
Phase 9, that groundwork needs re-running first.
