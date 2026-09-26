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

## The leak has a live silent-drop, found from the failing side

Predicted by "the rewrite, and the flag that repairs it" above, and then met
head-on while writing the acceptance test. Measured:

    our @OTHER = (7, 8); *crackers = \@OTHER; print "@OTHER\n";
      perl  7 8
      ours  7 8        store kept

    our @OTHER = (7, 8); *crackers = \@OTHER; print "@crackers\n";
      perl  7 8
      ours  (nothing)  THE STORE IS GONE

    *main::crackers = \@main::OTHER;
    print join('', (join($", @main::crackers) . "\n"));

Reading the ALIAS is the trigger. `@OTHER = (7,8)` is dropped from the emission
entirely -- no `ArrayLiteral`, no `EntryWrite` -- while the same program reading
`@OTHER` keeps it. And taking an ordinary ref (`my $r = \@SRC`) keeps it too, so
this is specific to the glob-bind path.

WHY, and it is the rewrite: the pass replaces `crackers`'s EntryDef
`sigil='*'` with a fresh `sigil='@'` node. A later read of `@crackers`
hash-conses to THAT node -- same package, sigil and symbol -- so the alias read
and the bind TARGET become one node, and the source array's store loses its
reachability. The consing that makes `@crackers` reach the right node is exactly
what collides here.

Keeping `sigil='*'` on the bind target removes the collision by construction:
the target is a glob, the read is an array, and they are different nodes
because they ARE different things.

It compiles and runs, printing nothing where perl prints `7 8` -- a silent wrong
answer, which is why no census caught it: `_resolve_glob_slots` reports the
RESOLVABLE case as success.

## LANDED. The deparser needed two spellings, both one line

**Status: DONE for the bind; the second-order store drop remains.**

The first attempt reverted on `**main::B = A`, and both halves of that turned out
to be one-line spellings rather than the wire negotiation they looked like:

    the target   s/\A[$@%&]// enumerated FOUR of the five sigils, so a `*`
                 survived and the branch prepended a second one. `**main::B`.
    the value    a `glob` Constant renders the BAREWORD -- right for
                 `close FOO`, wrong on the right of a glob assignment, where
                 `*main::B = A` makes `A` a bareword. Spelled in the `binds`
                 branch rather than in `_constant`, because the difference is
                 POSITION, not node kind: changing the shared renderer would
                 put a star on every bareword filehandle.

Three refusal sites removed: `_glob_bind`'s Glob check, `_resolve_glob_slots`'s
`'every slot'` and `'runtime'` branches. The lattice query replaced the
exact-match lookup -- more than one ref kind under the stamp means "do not
resolve", not "refuse".

    our @A=(1,2); *B = *A; print scalar(@A)
      perl  2
      ours  *main::B = *A;   -> 2

AND IT UNBLOCKED THE TWO t/ FILES IT WAS CHOSEN FOR. `base/rs.t` and
`comp/form_scope.t` had this as their last GAP; both now translate, render and
RUN. rs.t produces 44 output lines against perl's 44, with 18 differing -- from a
deleted graph to 26 of 44 lines correct.

    perl t/  GAP 6 -> 5    REFUSED 10 -> 9    ROUNDTRIP 12 (unchanged)

A REGRESSION ARRIVED WITH IT and was caught by the census, not the suite:
`undef(&main::x, $eff73)` -- `Too many arguments for undef operator`. The `undef`
Call carried a memory input, which is invisible while it stays a memory node and
renders as a SECOND ARGUMENT once something binds it. `undef` takes at most one.
Removed; the ordering comes from `control_in`, which is what places the
statement anyway. EMITS_INVALID_PERL went 0 -> 1 -> 0 inside one change.

## What is still open: the second-order store drop

Reading THROUGH the alias still loses the source's store, by both routes:

    *crackers = \@OTHER; print "@crackers"   -- via a ref bind
    *B = *A;             print "@B"           -- via a glob bind

Both compile, run, and print nothing. It is a REACHABILITY defect in the graph
rather than a spelling one -- `@OTHER = (...)` has no consumer once the read
goes through the alias -- so it needs its own fix and is TODO-marked in
t/wire-glob-slot-is-the-stamp.t by both routes.

## The first attempt, kept because the way it failed was the useful part

The producer half is small and the design holds. Both refusal sites were
removed -- `_resolve_glob_slots` (the pass) and `_glob_bind` (the producer) --
and in both the answer was the `*` sigil the fallback already supplied. The
lattice query works: `is_subtype_of` returns five ref kinds for `Scalar` and
`Ref`, exactly one for each leaf, none for `Glob`/`Str`.

THEN THE EMISSION BROKE, and it is the deparser's assumption rather than the
model's:

    our @A=(1,2); our @B; *B = *A; print scalar(@B)
      perl   2
      ours   **main::B = A;        syntax error

Two defects in one line. The deparser adds a `*` for the EntryWrite's `binds`
field AND the EntryDef now carries `sigil => '*'`, so the target gets two. And
the RHS lost its sigil entirely -- it spells a glob operand from a resolved
sigil it no longer has.

So the deparser's glob path is written for "the sigil was resolved to one of
@%&$", which is precisely the assumption the fix removes. That is the wire
question this document already flagged as the only negotiation: a consumer that
reads `sigil => '*'` needs a rule for it, and ours has none.

REVERTED RATHER THAN FORCED. Emitting `**main::B` is worse than the refusal it
replaced -- [[removing-a-gap-can-create-a-miscompile]] in the exact shape that
memory names. The producer change is ready and blocked on the consumer, which
makes it a two-sided change rather than the one-sided one it looked like.

Worth noting what the revert cost: nothing, because the tree was `git add -A`'d
first. A `git checkout` on those files is the command that silently discarded
four verified changes earlier the same day
([[a-checkout-reverts-more-than-the-experiment]]); staging first is what made it
safe, and the three surviving fixes were verified by running their tests after.

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
