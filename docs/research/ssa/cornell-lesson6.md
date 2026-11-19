# CS 6120 Lesson 6: Static Single Assignment (resource note)

**Authors, venue, year.** Adrian Sampson, Cornell University, CS 6120 "Advanced Compilers", Spring 2022 course page. (Author taken from the course; not named on the extracted page.)  **Source:** https://www.cs.cornell.edu/courses/cs6120/2022sp/lesson/6/

## In one paragraph

A short, friendly lecture page that introduces SSA from scratch using Bril, the course's teaching IR. It is the best first read in this collection for someone who has not met SSA before, and it sets an "implement it yourself" exercise.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Renaming.** Give every assignment its own name:

```
a = 4;  b = 2;  a = a + b;  print a
a.1 = 4;  b.1 = 2;  a.2 = a.1 + b.1;  print a.2
```

**Phi nodes.** After an `if` whose two arms assign `a`, a Phi is "a flow-sensitive copy": `a.4 = phi .left a.2 .right a.3` takes `a.2` if control came from block `.left`, else `a.3`.

**"The SSA philosophy".** Definitions *are* variables; instructions *are* values; arguments *are* data-flow edges. This is the mental step that leads to graph IRs such as the sea of nodes. An aside mentions basic block arguments (MLIR, Swift) as an alternative to Phis.

## Construction / algorithm (steps, complexity, inputs it needs)

The standard dominance-frontier method, as two pieces of pseudocode. Needs the control-flow graph, dominator tree and dominance frontiers (the blocks just beyond the region a block dominates).

1. For each variable, add a Phi to every block in the dominance frontier of each block that assigns it; repeat, since a Phi is itself an assignment.
2. Rename by walking the dominator tree with a stack of current names per variable.

Out of SSA: copy each Phi input at the end of its predecessor block and delete the Phi. No complexity discussion.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- Onboarding text to read before Click and Braun.
- Its warning matches a chalk bug class: the tricky part is "variables that are undefined along some paths", which students find "surprisingly difficult to get this right". B::SoN should give every lexical a defining node at its declaration. (Inference.)
- Its two checks carry over as tests: an "is it really SSA?" verifier, and comparing program output before and after conversion.
- The page shows Bril's older `phi`; Bril now also has a Pizlo-style `set`/`get` form (see pizlo-ssa.md).

## Limits and later work

An introduction only: no pruned/minimal distinction, no memory, no parallel-copy subtleties. It points to Boissinot et al. for out-of-SSA done properly.
