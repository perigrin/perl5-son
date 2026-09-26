# The slot is the stamp

`*X = EXPR` binds the glob slot named by EXPR's TYPE. Our lattice already
encodes that mapping, so the refusal is not a missing fact -- it is an
exact-match hash lookup against a lattice.

**Status:** DESIGN. Measured, not built.

## The measurements

Every case, run against 5.42.0:

    our $S="sc"; our @S=(1,2); our %S=(k=>1);
    sub b { *T = shift }

    b(\@S)   array=2   scalar=undef          only @
    b(\%S)   hash=1                          only %
    b(\$S)   scalar=sc array=0               only $
    b(\&C)   code=c                          only &
    b(*S)    scalar=sc array=2  code=...     EVERY slot
    b("S")   scalar=sc array=2  hash=1       EVERY slot -- by NAME

and the bindings are INDEPENDENT: binding `$` leaves a previously bound `@`
standing. One op, six behaviours, selected by the operand's type.

## The rule, entirely from the lattice

    my @kinds = grep { Stamp->new(type=>$_)->is_subtype_of($stamp) }
                qw(ArrayRef HashRef CodeRef ScalarRef GlobRef);

    exactly one kind   -> that slot, statically resolved   (the %SLOT leaves)
    five kinds         -> ONE slot, kind chosen at runtime (Scalar, Ref)
    none, and Glob/GlobRef/Str -> every slot

Measured against the real lattice:

    Scalar     ArrayRef,HashRef,CodeRef,ScalarRef,GlobRef
    Ref        ArrayRef,HashRef,CodeRef,ScalarRef,GlobRef
    ArrayRef   (none)
    ScalarRef  (none)
    Str        (none)
    Glob       (none)

No new table. `%SLOT` keeps the leaves; the non-leaf rows are a lattice query
over types the lattice already relates.

## What is wrong today

`_resolve_glob_slots` (lib/B/SoN.pm) reads the stamp -- correctly -- and then:

    my $sigil = $SLOT{$type};           # exact match, 4 keys
    if (!defined $sigil) { ... }         # -> delete the whole graph

Probed on base/rs.t's `*FH = shift`:

    GLOBPROBE symbol=FH type=Scalar value_op=Call

`Scalar` is not "we do not know". It is the honest position of a value whose
ref-kind inference has not narrowed, and the slot follows from whichever kind
it turns out to be. The pass treats a LATTICE POSITION as a MISSING ANSWER and
deletes the graph, which is
[[a-t2-difficulty-is-not-a-t1-refusal]]: the message even says "perl itself
defers the choice", the same sentence that marked three `goto` FACTs that
turned out to be artifacts.

## Two leaks this removes

**1. The rewrite, and the flag that repairs it.** The producer records
`EntryDef sigil='*'` -- our own comment calls it a "placeholder" -- and the pass
REWRITES it to `sigil='@'`. A `binds => True` field on the EntryWrite then tells
the deparser to undo that and print `*crackers` instead of `@crackers`
(Deparse.pm:2115). The IR round-trips through a lossy conclusion and carries a
repair flag for it. Keep the `'*'` and neither is needed.

**2. "which no single typed binding expresses".** That is our refusal for
`*B = *A`, and it is a statement about our model, not about perl: a `Glob` stamp
IS the expression -- every slot. Perl has one glob with four independent slots;
we modelled four unrelated variables and then could not say what a glob is.

## The slot is DERIVED, never STORED

The one design decision, and the measurements settle it. A stored slot would
have to write `Scalar` down as a sentinel, which is precisely the information
the stamp already carries at the precision inference reached -- and a later
fixpoint narrowing `Scalar -> ArrayRef` should change the slot for free. A field
computed at build time can disagree with the stamp that eventually lands; a
derived one cannot.

Cost: a consumer walks one edge to the operand instead of reading a field --
the same walk `_resolve_glob_slots` already does.

## What it buys

    *X = \@A      resolved statically, as today, but the EntryDef stays '*'
    *X = *A       EXPRESSIBLE: operand is Glob, so every slot
    *X = shift    EXPRESSIBLE: one slot, kind from the operand's stamp at
                  runtime. A backend narrows it with its own inference or
                  DECLINES the node -- T2's call, which is the whole point.

Blocked tier 2 files: base/rs.t (2 subs), cmd/switch.t (3), cmd/mod.t (1),
cmd/for.t (2), comp/form_scope.t (1). Not all of those refuse for this reason
alone -- rs.t's is second-order, and the others need their own checks first.

## Open

Whether the runtime-dispatch case needs a wire signal for chalk to DECLINE, or
whether reading the operand's stamp is enough. Reading the stamp is enough for
correctness; a signal is about whether chalk can refuse cleanly rather than
having to know the lattice. That is a question for chalk, and it is the only
part of this that is a negotiation -- see
docs/plans/2026-09-26-wire-additions-chalk-must-agree.md.

Related: [[a-t2-difficulty-is-not-a-t1-refusal]],
[[a-refusal-test-that-only-translates]],
[[removing-a-gap-can-create-a-miscompile]]
