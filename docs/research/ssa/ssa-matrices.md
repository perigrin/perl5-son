# Computing SSA Form with Matrices

**Authors, venue, year.** Quan Hoang Nguyen (University of New South Wales) and Bernhard Scholz (University of Sydney). Electronic Notes in Theoretical Computer Science 190 (2007), pages 121-132, Elsevier. **Source:** https://bernsteinbear.com/assets/img/ssa-matrices.pdf

*Extraction note: clean text. Matrix layouts are slightly ragged and the three performance charts are missing, but the equations and the worked example are legible.*

## In one paragraph

Building SSA needs three facts about the control flow graph: which blocks dominate which, each block's dominance frontier, and the iterated dominance frontier (where phis go). The fast algorithms for these are intricate and easy to get wrong. This paper shows that all three can be written as a handful of equations on tables of 0s and 1s, using only "and", "or", "not" and repeat-until-stable. It is much slower (cubic in the number of blocks) but takes very little code, and the authors propose it for two jobs: getting a prototype compiler working quickly, and checking the output of a faster implementation.

## Key ideas

**Terms.** Block x *dominates* y if every path from the start block to y passes through x. The *dominance frontier* DF(x) is the set of blocks y such that x dominates a predecessor of y but does not strictly dominate y itself; it is where x's control ends. The *iterated* dominance frontier of a set of blocks is what you get by taking frontiers repeatedly until nothing new appears. If S is the set of blocks that assign a variable, the iterated dominance frontier of S is where that variable needs phis (Cytron et al.).

**Sets as bit rows.** With n blocks, a set of blocks is a row of n bits. Blocks B0 and B2 out of six is `101000`.

**Relations as bit tables.** A relation between blocks ("x dominates y", "there is an edge from x to y") is an n-by-n table of bits.

**Boolean matrix product.** Multiplying a bit row by a bit table, with "and" for multiply and "or" for add, means: *take the rows of the table selected by the 1 bits and OR them together*. That is all the linear algebra needed. A Perl programmer can read it as a bitwise `|` over selected bit strings.

**Worked example** (the paper's Figure 2). Six blocks; a variable is assigned in B0 and B2, so `s = 101000`. The paper's matrix J has these rows:

```
B0: 000000
B1: 000001
B2: 010011
B3: 010011
B4: 010001
B5: 000000
```

`s . J` = row B0 OR row B2 = `000000 | 010011` = `010011`, that is, blocks B1, B4 and B5. Those are the blocks that need a phi for the variable. Once J exists, phi placement for any variable is one OR over a few rows.

## Construction / algorithm

Input: the CFG as a matrix A, where row y has a 1 in column p when p is a predecessor of y (the paper calls this the transposed adjacency matrix).

Three equations:

1. **Dominance matrix M** (row i, column j is 1 when j dominates i). Start by assuming every block is dominated by every block, except that the start block is dominated only by itself. Then repeat "a block's dominators are itself plus whatever dominates *all* of its predecessors" until stable. The paper expresses this with complements, as M = not f*(not M0, A, not I), where f* is its "extended transitive closure": the recurrence X = (A . X) and C, run to a fixed point.
2. **Dominance frontier matrix D** = transpose of (A . M with M's 1s removed). In words: "x dominates some predecessor of y" minus "x dominates y".
3. **Iterated frontier matrix J** = D+, the *transitive closure* of D (D or D.D or D.D.D ... until stable). Transitive closure is the "reachable in one or more steps" table.

Then for a variable with definition set s, the phi blocks are `s . J`.

**Complexity.** The closures are O(n^3) using Warshall's algorithm (the paper mentions asymptotically faster methods of about O(n^2.376 log n)). The paper states plainly that this is a "higher worst-case complexity class than the state-of-the-art".

**Measurements.** Implemented in Java inside an optimiser for LCC bytecode and run on the SPEC95 integer benchmarks, against Purdom-Moore and Lengauer-Tarjan for dominators and textbook algorithms (Muchnick; Cooper and Torczon) for frontiers. The matrix method was slowest in all three comparisons, showing the predicted cubic growth, and had the fewest lines of code in all three.

The paper covers computing the three relations only. Renaming variables is the usual second step and is not discussed.

## Memory, arrays, aliasing

Not addressed. The method only looks at the shape of the CFG and at which blocks define a variable. What kind of thing the variable is plays no part.

## Relevance to chalk / B::SoN

- **Adopt as a test oracle, not as the production algorithm.** This is the paper's own second recommendation. Chalk needs dominators regardless: scheduling floating nodes and several of the checks suggested in the other summaries depend on them. A second, independent implementation that is a few dozen lines of Perl over bit strings (`vec`, or string-wise `|` and `&`) can check the real one on every test program. The Perl sizing is my estimate; the paper reports only that its version was the shortest.
- **A checker for memory Phis (my inference).** In chalk's design memory is a single SSA variable. Let s be the set of blocks containing a memory write. Then `s . J` is exactly the set of join points that must carry a memory Phi (before pruning any that are unread). Comparing that set with the Regions where B::SoN actually created a memory Phi is a direct test for the "write floated off the chain" bug class: a write missing from the chain shows up as a required memory Phi that is absent, or as a memory Phi whose inputs are all the same version although a write lies on one path.
- **Cubic cost is acceptable here.** Perl subs are usually small. For a sub with 50 basic blocks the tables are 50 by 50 bits. For generated code with thousands of blocks, switch the check off.
- **It warns about nothing in particular,** except implicitly: the authors wrote it because the fast algorithms are "complex, time-consuming and error-prone to implement".
- **Does not apply to:** building the graph, typing, the memory model itself, or lowering to LLVM. It also needs a block-level CFG. A sea-of-nodes graph has to be viewed through its control nodes (Region, If, and so on) to get one (my inference).

## Limits and later work

Cubic time and n-squared bits of space, so it suits small graphs and offline checking. It produces *minimal* phi placement in Cytron's sense for arbitrary graphs, including irreducible ones, and not pruned placement (it does not consider whether the variable is still live). The paper positions itself against the more elaborate methods it cites: Lengauer-Tarjan and later linear-time dominator algorithms, Sreedhar and Gao's DJ-graphs, Aycock and Horspool's delete-the-extras method (minimal only for reducible graphs) and Brandis and Mössenböck's single-pass method (structured programs only). I found no later work building on it among the papers summarised here.
