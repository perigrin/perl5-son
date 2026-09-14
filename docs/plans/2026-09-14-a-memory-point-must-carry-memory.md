# A memory point must carry memory

**Date:** 2026-09-14
**Status:** FIXED for require/dofile. `comp/require.t` still refuses, for a
further cause not yet isolated.

## The invariant

Every point in the memory chain names the version it supersedes:

    EntryWrite   [slot, value, memory]
    Assign       [target, value, memory]
    Delete       [container, key, memory]
    Call         [args..., memory]        keys/values/each, push/…, shift/pop

That is what lets a consumer recognise the chain STRUCTURALLY. The
alternative -- a name list of "things that are memory points" -- fails
asymmetrically, which is this project's most-repeated defect.

## Who broke it

`require` and `dofile`. FromOptree advances memory for them, with a comment
saying exactly why:

> `require X; X->import(...)` is the runtime spelling of `use X`, and the
> import MUST NOT float above the require -- calling POSIX->import before
> POSIX is loaded is a different program.

but built the node with only its argument. Measured before the fix:

      5 Call in=[4] ci=0   name=require
      6 Call in=[3] ci=5   name=require

Two requires, ordered only by `control_in`. Nothing on the data side said
either was a memory point.

## What it cost

In `comp/require.t`, a merge of two memory chains looked like a value merge:

    1190 Phi in=[690:Call(require), 681:EntryWrite]  region=715

The deparse's `_is_memory` asked whether input 0 was memory, got
`Call(require)` -- which carried no memory input -- and answered no. The Phi
was taken for a VALUE Phi, which bound the EntryWrite as a chain effect whose
value is read, and then refused: "no rule for value node `EntryWrite`".

Three separate bugs were found and fixed on the way to that diagnosis, each
real on its own:

  1. `_is_memory` tested only input 0 of a Phi. A Phi merges two CHAINS and
     the arms can end in different kinds of effect, so every input has to be
     asked.
  2. Doing that recursively fanned out over a chain thousands of nodes long:
     comp/require.t did not finish in 180s, then hit perl's deep-recursion
     warning. It is now an iterative worklist with a per-sub cache.
  3. A loop-carried memory Phi names ITSELF across the back edge, so the walk
     needs a cycle guard -- a node already on the stack contributes no
     evidence.

## Still refusing

`comp/require.t` refuses on the same message after all of the above, so at
least one more node in that file's chain is a memory point that does not look
like one. Not yet isolated; the file is large (1190+ nodes) and each
diagnosis has been a separate investigation.

WORTH DOING AS A SWEEP RATHER THAN A CHASE: enumerate every site in
FromOptree.pm that calls `$sim->set_memory(...)` -- there are 31 -- and check
that each one's node also takes `$sim->memory` as an input. That converts an
open-ended diagnosis into a finite list, and it is the same shape as the audit
that would have caught require/dofile without the corpus pointing at it.

MOST OF THE 31 ARE FINE BY CONSTRUCTION: a memory Phi, or a site that forwards
another sim's chain (`set_memory($other_sim->memory)`). The ones to check are
those that pass a NODE THEY JUST BUILT.

A WIRE-SIDE SWEEP WAS TRIED AND DOES NOT DISCRIMINATE. Looking for "nodes
named in a memory position that do not themselves carry memory" reports 300+
Constants, 66 ArgsSources and so on, because the position test is
`@inputs > the declared operand count` and plenty of nodes legitimately have
an extra input. The producer-side audit is the one with a finite, checkable
answer; the wire does not carry enough to ask the question from outside, which
is itself the finding.

## The general rule, for new nodes

If a node calls `set_memory`, it takes a memory input. The two are the same
claim -- "I am a point in this chain" -- and stating only half of it leaves a
node that behaves like memory to the producer and like a value to everyone
else.
