# An element store in a nested one-armed branch: what the refusal is protecting

**Date:** 2026-09-12
**Status:** OPEN. The refusal STANDS. This records what an attempt measured, so
the next one starts from evidence rather than re-deriving it.
**Blocks:** `comp/use.t` (its only remaining blocker)

    GAP: an element store inside a nested one-armed branch is not yet lowered
         (needs the memory-Phi merge)

`lib/SoN/FromOptree.pm`, the statement-modifier handler inside an if/else arm.

## The shape

    my @a = (1,2);
    if ($a[0]) { if ($a[1]) { $a[1] = 9 } }
    my $v = $a[1];            # perl: 9

Only this combination refuses. Measured -- each of these already lowers:

    if ($a[0]) { $a[1]=9 }                     flat one-armed      CLEAN
    if ($a[0]) { $a[1]=9 } else { $a[1]=8 }    flat if/else        CLEAN
    if ($x) { if ($x) { $y=9 } }               nested, SCALAR      CLEAN
    if ($x) { if ($y) { print "in" } }         nested, void call   CLEAN

So it is not "nested", and not "element store" -- it is the pair.

## The one-term change is NOT the fix

The handler already builds the whole If/Proj/merge path; it is gated on
`$mem_branch`, which counts void calls and dies but not element stores. Adding

    _arm_has_element_store($op->other, $op->next)

to that gate makes every nested case report CLEAN -- and the graphs are WRONG.
The store and the memory-Phi are both built and both DEAD:

    memPhi 19 in=[5, 15]   consumers = DEAD
    Subscripts still threaded to MemStart: [6, 18]

Node 18 is the read AFTER the branch. perl says 9; the graph says 2. That is
precisely the silent drop the refusal's own comment records ("printed 1 where
perl printed 9, and both guard polarities printed the same thing"), so the
refusal has been doing its job. DO NOT lift it with this one-liner.

## Why the working shapes work

`StackSim::merge` already does everything: Region, scope Phis, stack Phi, AND
the memory-Phi over `[my_memory, other_memory]`. Nothing is missing there.

What differs is whether anything CONSUMES the result. Measured:

    flat one-armed    Phi 15 consumed by 16 EntryDef in=[15]
    flat if/else      Phi 17 consumed by 18 EntryDef in=[17]
    + a later read    Phi 15 consumed by 16 Subscript in=[4, 2, 15]
    NESTED            Phi 19 -> DEAD

In the flat cases `merge` mutates `$sim` in place and the walk continues on that
same sim, so the next read binds to the merged memory. In the nested case the
merge happens on a sim whose result the enclosing arm walk does not carry back
out to the continuation, so the later read is still bound to the pre-branch
`MemStart`.

A CONTROL effect does not notice this: the nested void-call case is correct
because the continuation `Print` is pinned via `control_in` on the merged
Region. A MEMORY effect does, because a later read reaches its memory by a DATA
edge that was already built against `MemStart` and pinning control does not
retroactively re-thread it.

(Two false readings on the way to this, both from counting only `inputs`: the
flat Phi looked dead until the separator's consumer was counted, and the
void-call Region looked dead until `control_in` was counted. Count both.)

## What a fix has to do

Carry the merged memory out of the nested arm walk into the enclosing sim, so
the continuation's reads bind to the memory-Phi rather than to the pre-branch
memory. The Phi itself is already correct -- it is reachability, not
construction.

Worth checking first whether this is the SAME defect as
`docs/plans/2026-09-06-keys-values-each-do-not-observe-stores.md`: there a
whole-aggregate read carries no memory input at all, here a read carries one
that is stale. Both are "the reader does not observe the store", from different
directions, and a fix for where memory reads bind may want to answer both.

## Not to be confused with

`my @a=(1,2); ... print "@a"` shows `join` taking the ORIGINAL element Constants
in every shape, working ones included. That is the whole-aggregate read issue
above, not the branch merge, and it is why "@a" is a bad probe for this bug --
use a single-element read (`my $v = $a[1]`) instead.
