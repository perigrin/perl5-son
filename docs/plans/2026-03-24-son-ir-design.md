# SoN: Sea of Nodes IR for Perl 5

## Context

Perl 5's compiled optree serves simultaneously as AST, IR, and execution
format. This coupling prevents global optimization -- the peephole optimizer
can only see adjacent ops, data flow is implicit in stack operations, and
there is no opportunity for dead code elimination, common subexpression
elimination, or loop-invariant code motion across basic blocks.

The Chalk compiler project has demonstrated that Perl semantics can be
represented in a Sea of Nodes intermediate representation with explicit
data flow edges, proper SSA-style control flow (If, Region, Loop, Phi),
and hash consing for structural deduplication.

This design describes `SoN`, a CPAN distribution that provides:

1. A standalone Sea of Nodes IR library suitable for representing Perl
   computations
2. An optree-to-SoN translator that walks perl5's compiled optree and
   produces SoN graphs
3. Text rendering and structural comparison tools for testing

The immediate use case is validating Chalk's compiler output against
perl5's own compilation of the same source code. The future use case is
feeding SoN graphs into optimization passes and an LLVM backend for
native code generation.

## Design Decisions

### Node Granularity: One Class Per Operation

Following Graal and libFIRM, each Perl operation (add, subtract, concat,
method call, etc.) gets its own node class. Type information is carried as
metadata ("stamps") on node edges, not baked into node class names.

This was chosen over:

- **Per-category nodes** (e.g., one BinaryOp class with an `op` field) --
  production SoN implementations don't do this. Per-operation classes
  enable optimization passes to pattern-match on node type directly.

- **Per-operation-x-type nodes** (e.g., IntAdd, FloatAdd as separate
  classes, like HotSpot C2) -- Perl's type lattice is semantic (Int, Num,
  Str, Scalar), not machine types (i32, i64, f32, f64). Baking the lattice
  into class names would be awkward and would require changing the class
  hierarchy as the type system evolves.

### Type System: The Formal Perl Type Lattice

The type lattice on SoN edges follows the formal definition from
https://pvm.tools/papers/perl-types-formal.html -- a characterization
of Perl's latent dynamic type system derived from operational semantics.

Key properties:

- A value belongs to a type if it survives coercion without losing
  information (syntactic preservation) AND satisfies all operational
  contracts (semantic fulfillment)
- Subtyping: Int < Num < Str < Scalar
- DualVars are in Scalar but not in Str or Num (correctly captures
  that optimization is unsafe for them)
- This describes what Perl values already *are*, not an imposed
  external type system

Stamps are initially `Unknown` and refined by type inference passes.

### Relationship to Chalk

SoN and Chalk are parallel implementations of the same IR design. Chalk
does not depend on the SoN dist. The shared contract is the node
vocabulary and graph structure, not Perl code.

Chalk produces SoN graphs by parsing Perl source through its Earley
parser. SoN::FromOptree produces SoN graphs by walking perl5's compiled
optree. Comparing the two validates that Chalk's frontend produces
correct graphs.

Future optimization passes and the LLVM target will consume SoN graphs
regardless of which frontend produced them.

### Non-Core Module with Thin XS

The distribution ships on CPAN with no core modifications required. The
optree walker uses B:: for most introspection. A thin XS component
exposes `PadnameFIELDINFO` (field index, field stash, param name) which
B:: does not currently provide. This is needed for `feature class` field
access nodes.

## Architecture

### SoN::IR -- The Graph Library

#### Node Base Class

Every node has:

- `id` -- stable content-based identifier (for hash-consed data nodes)
  or sequential unique ID (for CFG nodes)
- `inputs` -- ordered list of producer nodes (data flow edges)
- `consumers` -- reverse edges (use-def chains), maintained automatically
- `stamp` -- type lattice position on the node's output

#### CFG Nodes (never hash-consed, unique by identity)

- **Start** -- entry point of the computation graph
- **Return** -- exit point, carries the return value
- **If** -- conditional branch, produces two control outputs
- **Proj** -- projects one output from a multi-output node (true/false
  from If)
- **Region** -- control flow merge point
- **Loop** -- loop header with entry and backedge control inputs

#### Data Nodes (hash-consed for deduplication)

- **Constant** -- compile-time constant with value and stamp
- **Phi** -- value selection at Region/Loop merge points

#### Operation Nodes (~50-70 types, one per Perl operation)

Arithmetic: Add, Subtract, Multiply, Divide, Modulo, Power, Negate
String: Concat, Repeat, Substr, Index, Length
Comparison: NumEq, NumLt, NumGt, NumLe, NumGe, NumNe, NumCmp,
            StrEq, StrLt, StrGt, StrLe, StrGe, StrNe, StrCmp
Logical: And, Or, Not, Defined
Bitwise: BitAnd, BitOr, BitXor, LeftShift, RightShift, Complement
Assignment: Assign, CompoundAssign
Call: Call (with metadata for dispatch kind: direct, method, builtin)

#### Access Nodes

- **PadAccess** -- lexical variable (pad index, statically known)
- **FieldAccess** -- class field (field index + class stash, from
  PadnameFIELDINFO)
- **StashAccess** -- package variable (stash name + GV name, dynamic
  hash lookup)

#### NodeFactory

Singleton factory implementing hash consing:

- Data nodes cached by content hash: `"Operation|input_id_1|...|attr=val"`
- CFG nodes bypass cache, receive sequential unique IDs
- On creation, registers bidirectional use-def edges (producer.consumers
  += consumer, consumer.inputs += producer)

### SoN::FromOptree -- The Optree Translator

#### Stack Simulation Algorithm

Walks the optree in execution order (following `op_next`), maintaining:

- `virtual_stack` -- array of SoN node references
- `mark_stack` -- PUSHMARK positions for LISTOP argument collection
- `scope` -- immutable variable bindings (pad index -> SoN node),
  copy-on-write for branching
- `control` -- current CFG node
- `visited` -- op addresses already processed (merge point detection)

For each op:

1. Consult OpMap for stack effect and SoN node type
2. Pop inputs from virtual_stack
3. Create SoN node via NodeFactory
4. Push output onto virtual_stack (if any)

Special handling:

- **LOGOP** (and, or, cond_expr): snapshot state, walk both paths
  (op_next and op_other), detect merge point (op address in visited),
  create Region + Phi for any scope variables that differ
- **LOOP** (enterloop): create Loop CFG node, install Phi sentinels for
  in-scope variables, walk body, resolve sentinels with backedge values
- **Skip ops**: OP_NULL, OP_PUSHMARK (record mark position only),
  OP_ENTER, OP_LEAVE, OP_NEXTSTATE -- interpreter bookkeeping not
  represented in SoN

#### OpMap

Mapping table from perl opcodes to SoN behavior:

- Stack pop count (fixed or mark-relative)
- SoN node type to create
- Stack push count (0 or 1)
- CFG flag (requires branch/loop handling)
- Skip flag (interpreter bookkeeping, not represented)

Generated from `regen/opcodes` or hand-maintained. Starts with the
subset Chalk handles, expands incrementally.

#### Entry Point

```perl
use SoN::FromOptree;

my $graph = SoN::FromOptree->translate(\&Some::function);
```

Takes a code reference, obtains the B::CV via `B::svref_2object`,
walks from `$cv->START`, returns a `SoN::IR::Graph`.

### SoN::Render::Text -- Text Dump

Deterministic text format for testing and debugging:

```
%0  = Start
%1  = Constant(42)                          [Int]
%2  = PadAccess(targ: 1, name: '$x')       [Unknown]
%3  = Add(%1, %2)                           [Unknown]
%4  = Return(%0, %3)
```

Node IDs assigned by topological sort for deterministic output.
Hash-consed nodes produce identical IDs regardless of frontend.

### SoN::Compare -- Structural Comparison

Takes two `SoN::IR::Graph` objects, produces a diff:

- Nodes present in one graph but not the other
- Nodes with same operation but different inputs
- Stamp disagreements

Initially strict structural identity. Will loosen to semantic
equivalence as optimization passes cause the two frontends to diverge.

Test usage:

```perl
my $chalk_graph = Chalk::compile($source);
my $perl_graph  = SoN::FromOptree->translate(\&compiled_sub);
my $diff = SoN::Compare->diff($chalk_graph, $perl_graph);
ok($diff->is_empty, 'Chalk matches perl5') or diag($diff->to_text);
```

### FieldInfo.xs -- Thin XS Component

Exposes two functions that B:: does not provide:

- `SoN::FieldInfo::is_field($padname)` -- returns whether this padname
  is a class field
- `SoN::FieldInfo::field_info($padname)` -- returns (fieldix, fieldstash,
  paramname, default_flags) for class fields

Implemented against `struct padname_fieldinfo` from pad.h. Only XS in
the distribution.

## Distribution Layout

```
SoN/
  lib/
    SoN/
      IR/
        Node.pm
        NodeFactory.pm
        Graph.pm
        Stamp.pm
        Node/
          Start.pm, Return.pm, Region.pm, If.pm, Proj.pm, Loop.pm
          Phi.pm, Constant.pm
          Add.pm, Subtract.pm, Multiply.pm, ... (~50-70 operation nodes)
          PadAccess.pm, FieldAccess.pm, StashAccess.pm
          Call.pm
      FromOptree.pm
      FromOptree/
        StackSim.pm
        OpMap.pm
      Render/
        Text.pm
      Compare.pm
  xs/
    FieldInfo.xs
  t/
  cpanfile
```

Requires perl 5.42.0+.

## Future Path

This design establishes the SoN IR as the shared contract between
frontends (Chalk's parser, perl5's optree) and backends (optimization
passes, LLVM target). The immediate deliverable is the optree translator
and comparison tool. Future work:

1. **Optimization passes** operating on SoN::IR graphs -- DCE, CSE, LICM,
   strength reduction. Shared between Chalk and perl5 pipelines.
2. **Type inference** using the formal lattice to refine stamps from
   Unknown to specific types, enabling coercion elimination.
3. **LLVM target** lowering typed SoN graphs to LLVM IR for native code
   generation. Shared between both pipelines.

The pipeline:

```
Chalk parser ------> SoN::IR --> Optimization --> LLVM --> machine code
                       ^
perl5 optree -----> SoN::FromOptree
  (toke.c/perly.y)
```
