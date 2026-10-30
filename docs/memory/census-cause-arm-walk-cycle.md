# Census cause: an if reached again in its own arm (361 -> 362, pin a3fbb19d)

**Cause:** "an if is reached again inside its own arm -- the arm walk
cycles". It held 216 and, once its earlier refusals were cleared, 169.

## What changed (chalk d3a7de71, a3fbb19d)

The arm walk (`_collect_body_recursive`) follows data edges as well as
control edges, so it can reach a node that is unpinned (it has no
`control_in`). An unpinned node is owned by the arm unless it reads a merge
the arm does not contain. That test widened in two steps:
- **Directly** (d3a7de71): an input that is a statement pinned past the
  merge, such as the join of `return "@l"` reading the `push @l` after the
  if.
- **Through values** (a3fbb19d): `ord($c[$k + 1])`, where `$k` is an Add
  of an earlier if's merge phi.

Taken into the arm, such a read lowered the merge's phi and forced the If
again. In the second shape it also emitted IR lli rejected.

**Round-tripped:** 216. 169 now stops at "an array index with
repr=Unknown".

## Found on the way (silent wrong answer, chalk 8353bbcf)

`my @l = (1); if ($c) { @l = (5) } push @l, 9; print "@l"` printed `5` for
perl's `5 9`. After the if, @l is a TernaryExpr of the two literals, and
the read lowered it again: a fresh array, so the push was lost. An Array-
or Hash-stamped ternary is one container, so it is cached. Reported.

## Also this stretch (169's earlier refusals)

- An argument nothing typed is bound as it was lowered.
- A memory-flagged Phi of list assignments is a memory Phi.
- Untyped arithmetic lowers its operands before reading their reprs.
- A Scalar argument read bound to a reference passes the reference on.

## 169 round-trips (362 -> 363, pin fad1ec84)

The last refusal was "an array index with repr=Unknown". `_index_i64` read
the index's repr before lowering it, and an Add nothing typed is typed only
by its lowering. It now lowers first. **Lesson:** every reader of
`_repr_of` on a node nothing typed must lower that node first. This ordering
bit four times this stretch: binop operands, Concat operands, grep tests,
and indexes.
