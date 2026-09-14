# `keys`/`values`/`each` do not observe stores

**Date:** 2026-09-06
**Status:** FIXED 2026-09-14. Found while threading `delete` on the memory chain; NOT fixed
there, because it is a different op family and an unrelated change.

## The defect

`keys`, `values` and `each` are declared in the OpMap as

    keys           => [1, 'Call',       1, 0],
    values         => [1, 'Call',       1, 0],
    each           => [1, 'Call',       1, 0],

one operand, no memory input. So an aggregate-wide read takes the CONTAINER
NODE and nothing else, and does not observe any store threaded onto that
container. Measured on 5.42.0:

    my %h=(a=>1); $h{b}=2; print scalar(keys %h)
      perl : 2
      graph: Call(keys) in=[HashLiteral]   -- the pre-store literal, so 1

    my %h=(a=>1,b=>2); delete $h{a}; print scalar(keys %h)
      perl : 1
      graph: Call(keys) in=[HashLiteral]   -- the pre-delete literal, so 2

The element-read path is correct here and shows the contrast: a `Subscript`
carries `[container, key, memory]` and threads to whatever last wrote, so
`defined($h{a})` after a delete answers correctly while `keys %h` beside it does
not.

## Why it is the same class as the delete defect

This is the silent-drop class the refuse-or-lower contract exists to prevent: a
mutation the graph does not thread. `delete` was REFUSED for exactly this
(`%UNBUILT_OP_GAP`) and has now been lowered with `[container, key, memory]`.
The same argument applies to a whole-aggregate read, from the other side -- the
store is threaded, the READER is what fails to look.

`Count` already had this fixed in the same direction: it used to extend UnaryOp
(one input, no memory slot) and "that arity was the whole bug" -- see the
`_make_count` comment. `keys`/`values`/`each` are the remaining ops of that
shape.

## What a fix needs

A memory input on the read, and a decision per op:

  - `keys`/`values` are pure reads of a memory-dependent container: they need
    `[container, memory]`, and their result stamps stay as they are.
  - `each` is NOT a pure read -- it advances an iterator stored on the hash, so
    it mutates and must advance memory as well, like `Delete` does. Two calls to
    `each` on one hash are different values even with identical inputs, so it
    also needs the never-hash-consed treatment (a counter field, as
    `Delete`/`CellWrite`/`EntryWrite` have).

The `Call` node has no memory slot today, so either these three get their own
node kinds (as `Exists`, `Count` and `Delete` did) or `Call` grows one. The
former matches every precedent in this repo.

## Not measured yet

Whether anything in the corpus currently depends on this. `comp/require.t`'s
blocker was `delete`, not `keys`; this was found by reading the generated graph
beside it rather than from a failing file.

## Fixed (2026-09-14)

`keys`, `values` and `each` now take `[container, memory]`, so a store to the
container is observed. Measured:

    my %h=(a=>1); $h{b}=2; print scalar(keys %h)
      perl   : 2
      before : Call(keys) in=[HashLiteral]        -- reports 1
      after  : Call(keys) in=[HashLiteral, Assign] -- reads at the store

`each` ALSO ADVANCES MEMORY, which is what separated it from the other two.
It consumes an iterator stored on the hash -- measured, after one `each` a
fresh loop over a 3-key hash yields only 2 more keys -- so two calls on one
container are different values and must not hash-cons into one node. It is
pinned on control and advances memory, exactly as push/unshift/splice do.

VERIFIED BY EXECUTION, not only by reading the graph: the deparse oracle
round-trips `my %h=(a=>1); $h{b}=2; print scalar(keys %h)` to a program that
prints 2.

Two emitter bugs surfaced on the way, both in SoN::Deparse rather than the
producer:

  - A MEMORY INPUT IS AN EDGE, NOT AN ARGUMENT. Rendering all inputs put the
    MemStart in the argument list.
  - THE STAMP CARRIES THE CONTEXT. A counted `keys` is stamped Int; emitting
    the list form for it printed the keys themselves ("ba" where perl printed
    2).
