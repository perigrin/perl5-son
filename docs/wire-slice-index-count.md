# `Slice.index_count`

A `Slice`'s inputs are `[indices..., container]` — container LAST and
exactly one. Measured on `@a[0,2]` (`Slice(0, 2, ArrayLiteral)`) and
`@h{'k1','k2'}` (`Slice('k1', 'k2', HashLiteral)`).

A LIST slice has no container node. `(qw(p q r))[1]` slices a flat list of
values rather than a named aggregate, so its inputs are
`[indices..., values...]` and neither length is recoverable from the other.
`index_count` says where the split falls.

## What an un-updated consumer sees

The field absent, which reads as 0 — the container form. That is correct
for every `aslice`/`hslice` node, whose wire is byte-identical to before.

A LIST slice reaching such a consumer is read as a container slice, taking
the last input as the container. It will be wrong, but it was wrong before
too: `lslice` previously had a FIXED arity of 2 in the op table, so the
generic dispatch popped the last two stack entries and built
`Slice("q","r")` — dropping the index and the first value, and leaving the
rest to leak into the enclosing expression.

## Values

    0 (or absent)   the CONTAINER form: every input but the last is an index
    N > 0           the LIST form: the first N inputs are indices, the rest
                    are the values being sliced
