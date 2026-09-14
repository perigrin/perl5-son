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

## The audit, run

Of the 31 `set_memory` sites, most are fine by construction -- a memory Phi,
or a site forwarding another sim's chain. The ones that pass a NODE THEY JUST
BUILT were checked, and one more violates the invariant:

**`RegexSubst`** (two sites, FromOptree.pm ~1446 and ~8750) calls
`set_memory($node)` -- a destructive s/// stores into its target and a later
read must observe it -- while its inputs are
`[target, pattern?, replacement?]`. Measured on
`our $g = "aaa"; $g =~ s/a/b/; $g =~ s/b/c/`:

    11 RegexSubst in=[3]    no memory input
    12 RegexSubst in=[11]   chained through its TARGET, not through memory

The ordering happens to fall out of the data edge, which is exactly how a
missing memory edge stays invisible until something else needs it.

NOT FIXED, because it needs a wire decision. RegexSubst has TWO optional input
slots, so appending memory makes position ambiguous -- a 2-input node could be
[target, pattern], [target, replacement] or [target, memory]. It already
carries `pattern_is_input` for this reason; doing memory properly means a
second flag or always-present slots. Pinned as TODO in
t/wire-global-state-call-carries-memory.t.

Worth noting HOW it was found: the producer-side audit, with no corpus file
pointing at it. That is the argument for running the audit rather than
chasing files.

## The general rule, for new nodes

If a node calls `set_memory`, it takes a memory input. The two are the same
claim -- "I am a point in this chain" -- and stating only half of it leaves a
node that behaves like memory to the producer and like a value to everyone
else.

---

## Unrelated, recorded here so it is not lost: a Slice over a string

`base/lex.t` refuses with "a Slice over an anonymous `Constant` has no
container to name". Measured:

    1098 Constant  value="b"        stamp=Str
    1099 Slice     in=[6, 1098]     stamp=List
    1100 Coerce    in=[1099]        List -> Str
    1101 StrEq     in=[1100, 1098]

`Slice`'s operands are [indices, container], so the CONTAINER is a string
Constant. A slice over a string is not a Perl operation, so this graph is
probably wrong rather than merely unspellable -- but it was not isolated.

The construct is one of base/lex.t's caret-variable interpolation tests
(`"${^TEST}[0]"`, `"${^TEST[0]}"`, `"${ ^TEST [1] }"` around lines 168-174),
which differ in whether the subscript is inside or outside the braces. perl
folds most of each away before B::SoN sees it, and a reproduction using an
ordinary `@TEST` does not produce the shape -- `@{^TEST}` is a different
variable from `@TEST`.

Worth an hour with `-MO=Concise` on those four lines specifically. Not worth
guessing at.
