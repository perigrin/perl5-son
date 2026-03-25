# SoN - Sea of Nodes IR for Perl 5

SoN translates perl's compiled optree into a [Sea of Nodes][son]
intermediate representation with explicit data flow edges. It's the
kind of IR that production compilers like HotSpot, Graal, and V8's
TurboFan use internally, applied to Perl.

The idea is straightforward: perl's optree is a stack machine where
data flow is implicit. SoN makes it explicit. Every value has a
visible producer and consumer. Control flow is represented as proper
graph nodes (If, Region, Loop) with Phi nodes at merge points.
This makes the program structure available for analysis and
optimization in ways the flat optree can't support.

## What It Does

Given a compiled subroutine, SoN walks the optree and produces a
graph:

```perl
use SoN::FromOptree;
use SoN::Render::Text;

sub magnitude ($x, $y) { $x * $x + $y * $y }

my $graph = SoN::FromOptree->translate(\&magnitude);
print SoN::Render::Text->new->render($graph);
```

Output:

```
%0 = Start
%1 = PadAccess(targ: 1, name: '$x')
%2 = Multiply(%1, %1)
%3 = PadAccess(targ: 2, name: '$y')
%4 = Multiply(%3, %3)
%5 = Add(%2, %4)
%6 = Return(%0, %5)
```

For `feature class` methods, field access is resolved with the
correct field index and class stash:

```
%0 = Start
%1 = FieldAccess(index: 0, stash: 'Point')
%2 = FieldAccess(index: 1, stash: 'Point')
%3 = Add(%1, %2)
%4 = Return(%0, %3)
```

## Type Lattice

SoN carries type information on node edges using the formal Perl
type lattice from [pvm.tools/papers/perl-types-formal.html][types].
This isn't an imposed type system — it's a formalization of what Perl
values already are. `"42"` is simultaneously `∈ Int`, `∈ Num`, and
`∈ Str` because it survives round-trip coercion through all of them.

The subtyping chain `Int ⊂ Num ⊂ Str ⊂ Scalar` tells you what
operations are safe without runtime checks. Constants are stamped
automatically; future type inference passes will propagate stamps
through the graph.

## Components

- **SoN::IR::Node** — Base node class with use-def chains. 6 CFG
  nodes (Start, Return, Region, If, Proj, Loop) and 49 operation
  nodes covering arithmetic, string, comparison, logical, bitwise,
  assignment, call, access, and data merge (Phi).

- **SoN::IR::NodeFactory** — Hash consing for data nodes. Identical
  computations (same operation, same inputs) share a single node
  instance. CFG nodes get unique identities. This gives you common
  subexpression elimination as a structural property of the graph.

- **SoN::IR::Stamp** — The type lattice. Immutable value objects
  with `is_subtype_of`, `meet` (greatest lower bound for Phi nodes),
  and `join` (least upper bound for branch merging).

- **SoN::IR::Graph** — Container with topological iteration and
  node-by-id lookup.

- **SoN::FromOptree** — The optree translator. Walks the `op_next`
  chain using a virtual stack to reconstruct data flow. Handles
  branches (and/or/ternary → If+Proj+Region+Phi), loops (while/for
  → Loop+Phi for loop-carried variables), try/catch, subroutine and
  method calls, and `feature class` field access.

- **SoN::FromOptree::OpMap** — All 426 perl opcodes mapped to SoN
  node types with stack effects and control flow flags.

- **SoN::FieldInfo** — Thin XS exposing `PadnameFIELDINFO` that B::
  doesn't provide. Returns field index, class stash, param name, and
  default flags for `feature class` fields.

- **SoN::Render::Text** — Deterministic text dump for debugging and
  test snapshots.

- **SoN::Compare** — Structural graph diff matching data nodes by
  content hash and CFG nodes by topology.

## Why

This project grew out of two observations. First, the
[Chalk][chalk] compiler demonstrated that Perl semantics can be
represented in a Sea of Nodes IR — that it's not just a trick for
statically-typed languages. Second, perl's optree couples the IR and
execution format, which limits optimization to local peephole
patterns. Separating them opens the door to global analysis.

The immediate use case is comparing Chalk's SoN output (from parsing
Perl source) against perl5's SoN output (from the optree translator)
to validate that Chalk's frontend produces correct graphs. The future
use case is feeding SoN graphs into optimization passes and an LLVM
backend for native code generation.

The pipeline looks like this:

```
Chalk parser ──→ SoN IR ──→ Optimization ──→ LLVM IR ──→ native code
                   ↑
perl5 optree ──→ SoN::FromOptree
```

Chalk and SoN are parallel implementations of the same IR design.
They don't depend on each other. Improvements to optimization passes
or code generation targets benefit both.

## Requirements

Perl 5.42.0 or later. A C compiler for the FieldInfo XS component.

## Installation

```
perl Makefile.PL
make
make test
make install
```

## Status

This is early-stage infrastructure. The optree translator handles
straight-line code, branches, loops, calls, try/catch, and feature
class fields. The type lattice is implemented but inference passes
haven't been written yet. There's no LLVM target yet.

What works today: translating real Perl subroutines to SoN graphs,
rendering them as text, and comparing graphs structurally.

## License

Same terms as Perl 5 itself.

## Author

Chris Prather <chris@prather.org>

[son]: https://en.wikipedia.org/wiki/Sea_of_nodes
[types]: https://pvm.tools/papers/perl-types-formal.html
[chalk]: https://github.com/perigrin/chalk
