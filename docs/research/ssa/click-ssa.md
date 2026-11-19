# A Simple Graph-Based Intermediate Representation

**Authors, venue, year.** Cliff Click and Michael Paleczny. ACM SIGPLAN Workshop on Intermediate Representations (IR'95), San Francisco, January 1995.  **Source:** https://bernsteinbear.com/assets/img/click-ssa.pdf

## In one paragraph

This is the founding description of what is now called the "sea of nodes". A program is one graph. Every operation (an add, a branch, a memory write) is a node; every edge points from a node to the node that produced one of its inputs. There are no separate "basic blocks containing instructions": the places where control flow joins are themselves nodes (`Region`), branches are nodes (`If`), and even "the state of memory" and "the state of the outside world (I/O)" are ordinary values that flow along edges. Because everything is the same kind of thing, the same small pieces of code can optimise data, control and memory. The paper describes the node kinds, an execution model, a compact C++ implementation, and shows that cheap optimisations done *while the graph is being built* get almost all the benefit of expensive whole-program ones.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**A value is the node that computes it.** In SSA (static single assignment: every variable is assigned in exactly one place) a variable name is just a label for one computation. Click drops the label: `a = b + c` is an `Add` node with two input edges, to the node for `b` and the node for `c`. Inputs are ordered and edges carry no labels; you read "who feeds me" with one pointer hop.

**Control is a value too.** A `Region` node replaces a basic block: its inputs are the control values arriving from each predecessor and its output is the merged control. An `If` node takes control and a true/false value (the predicate) and sends control one of two ways.

**Phi sits beside Region.** A `Phi` ("at this merge point, pick the value from whichever way we came") has the `Region` as its control input, and its i-th data input lines up with the Region's i-th control input. That pairing is what makes the graph self-describing: you can tell *when* each Phi input is chosen without looking anything up elsewhere.

**Projections split multi-result nodes.** Some nodes produce several things at once. Rather than labelling edges, such a node produces one tuple, and tiny `Projection` nodes each pick one field out. `If` produces (true-control, false-control); `Start` produces (initial control, each parameter, initial memory, initial I/O state); a call produces at least (control, memory, I/O, result). Projections cost nothing at run time.

**Optional control edges.** An ordinary data node may keep an edge to its Region saying "I live in this block". The edge is not always required; dropping it lets the node "float" so later passes can move it, at the price of needing a scheduler to put it back somewhere legal (see the companion Global Code Motion paper).

Worked example (the Perl is my adaptation of the paper's Figures 3-5):

```perl
my $x;
if ($c) { $x = $a + 1 } else { $x = $a * 2 }
return $x;
```

```
start  = Start
ctl0   = Proj(start, control)     a = Proj(start, param a)    c = Proj(start, param c)
iff    = If(ctl0, c)
t      = Proj(iff, true)          f = Proj(iff, false)
x1     = Add(a, 1)                x2 = Mul(a, 2)        # floating: no block needed
r      = Region(t, f)
x3     = Phi(r, x1, x2)           # input 1 pairs with t, input 2 with f
         Return(r, x3)
```

**Execution model.** A single control "token" hops between `Start`, `If`, `Region` and `Stop` nodes, just as control moves between blocks. Data nodes have no token: their outputs are simply a function of their inputs. A `Phi` latches the matching input at the moment the token enters its `Region`. Every cycle in the graph passes through a `Phi` or `Region`; there is never a loop of pure data nodes.

## Construction / algorithm (steps, complexity, inputs it needs)

The paper does not give a full SSA-construction algorithm; it says the parser builds SSA at parse time and refers to Click's thesis. What it does describe:

1. **Build nodes as you parse.** Each new node is immediately offered to a "peephole": before anything else points at it, ask (a) does it compute a constant? (b) is it an identity on an input (`x - 0` is `x`)? (c) is there already a node with the same operation and same inputs (hash-table lookup, i.e. value numbering)? If so, throw the new node away and use the existing one.
2. During value numbering, **ignore the control input** of nodes that cannot fault, so equal computations in different branches merge. The surviving node may then not sit above all its users, so a Global Code Motion pass must later choose a legal position.
3. This parse-time analysis is "pessimistic": it knows nothing about code not yet parsed, so it is weak around loops. Stronger global passes (conditional constant propagation etc.) run afterwards and need def-to-use edges, which are built in a batch just before and discarded after.

Measured result: on 52 Fortran/C routines, parse-time peephole plus Global Code Motion was within about 1-2% (total 1.9%, average 0.8%) of the full global optimiser, and using the peephole made total compile time 6.3% lower.

## Memory, arrays, aliasing (what it says, or "not addressed")

Section 2.5 is short and is the core of chalk's current design discussion.

- **Memory is one value, called the STORE** (the whole of memory, not the write instruction). `Start` plus a `Projection` yields the initial STORE.
- A **Load** node takes (STORE, address) and produces a value. It does *not* produce a new STORE.
- A **Store** node takes (STORE, address, value) and produces a *new* STORE.
- **Phi merges STOREs** at control joins exactly as it merges any other value.
- **No anti-dependences.** An anti-dependence is an edge from a read to the write that must come after it. The graph has none: two Loads from the same STORE may be reordered freely. The catch is that a careless ordering could place a Load of the old STORE *after* the Store that replaced it, which would mean keeping two copies of memory alive. The scheduler avoids this by treating memory like a single machine register with infinite spill cost; the paper says for the STORE this always succeeds.
- **It is deliberately coarse.** "A better design would break the global STORE into many smaller, unrelated STOREs. Every independent variable or array would get its own STORE", and operations on separate STOREs proceed independently. Pointer analysis could refine further.
- **I/O is a second, separate state value.** It is treated like memory except that both `Read` and `Write` produce a new I/O state, which forces I/O into a single fixed order. At program exit the I/O state is required; the STORE is not.
- **Calls** take and return at least control, STORE and I/O.
- Arrays as such, and alias analysis, are not addressed beyond the one-STORE-per-array remark.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Direct match for the current design.** "One memory chain from MemStart; writes produce new versions; reads name the version they see; Phi merges memory" is this paper's Section 2.5 almost word for word. Explicit `Store`/`Load` nodes are Click's original choice.
- **I/O and `die` ordering separate from memory: adopt.** Click already keeps I/O as its own threaded state, and makes *reads* of I/O produce a new state so nothing reorders. For `die` and other faulting operations, the mechanism here and in the GCM paper is a control input, not a memory edge. (Inference: three chains, memory, I/O, control, is the faithful reading of Click for Perl.)
- **Alias-class slices: endorsed as the obvious next step**, on the condition that the classes really are independent. For Perl that is the hard part (aliases via `\`, `local`, `@_`, ties); starting with one chain and splitting later is consistent with the paper.
- **The bug class "writes that float off the chain".** In this model a Store is only alive because something consumes the STORE it produces: a later Store, a Load, a Phi, a call, or the exit. A Store whose output nobody uses is dead code by construction. So the structural invariant chalk wants can be stated in Click's terms: every memory-writing node takes a memory input and its memory output is reachable from the final memory at `Return`/`Stop`. Note the paper says the STORE is *not* required at program exit; for Perl subs, whose callers observe package variables and container contents, the final memory must be an input to `Return`. (Inference.)
- **Load/Store ordering when lowering.** T2 must emit every Load of memory version N before the Store that turns N into N+1. The graph does not have an edge saying so; the scheduler must enforce it. LLVM IR has implicit memory, so a mis-ordered load silently reads the new value.
- **Peephole at construction.** B::SoN can fold constants and value-number as it walks the op tree. This also bears on "typing variables by use instead of declaration": each node class should carry its own type rule, so a variable's type comes from the node that defines it.
- **Does not apply directly:** the C++ layout tricks, the Fortran benchmarks, and the naive copy insertion (T2 hands Phis to LLVM instead).

## Limits and later work

Memory is one undivided chain. No construction algorithm is given (see the Braun et al. and libFIRM summaries for one that fits). Exceptions are only touched on. Scheduling is deferred to "Global Code Motion / Global Value Numbering" (Click, PLDI 1995). The design became the HotSpot server compiler's IR; libFIRM adopts it with a `Sync` node for memory slices.
