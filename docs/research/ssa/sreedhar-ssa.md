# A Linear Time Algorithm for Placing phi-Nodes

**Authors, venue, year.** Vugranam C. Sreedhar and Guang R. Gao (School of Computer Science, McGill University, Montreal). POPL '95, San Francisco, January 1995, pages 62-73. **Source:** https://bernsteinbear.com/assets/img/sreedhar-ssa.pdf

*What I read and how: all 12 pages, as page images rendered from the PDF at 120 dpi, because the extracted text interleaves the two columns and scrambles the pseudocode. Everything was legible, including Algorithm 3.1, Algorithm 4.1 (Main, Visit, InsertNode, GetNode), the lemmas, Figures 1 to 4 and the table in Figure 7. The algorithm below is transcribed from the paper's pseudocode, not reconstructed. The bar charts (Figures 5, 6, 8) I read for their shape only.*

## In one paragraph

The standard way to decide where phi functions go (Cytron et al.) first computes a table called the dominance frontier for every block, then iterates over it. That table can be quadratically large even though the final answer is small. Sreedhar and Gao find the phi locations for a set of defining blocks directly, in time proportional to the number of edges in the control flow graph, without building the table. Their tool is a new picture of the program, the *DJ-graph* (the dominator tree plus "join" edges), and a small data structure they call the *PiggyBank*. Cytron and Ferrante had said that linear time "necessitates placing phi-nodes without computing or using dominance frontiers"; the paper presents itself as the positive answer to that open problem.

## Key ideas

**Terms** (section 2). In a flowgraph (control flow graph, CFG) node x *dominates* y if every path from START to y passes through x; it *strictly* dominates y if also x is not y. The *dominator tree* hangs each node under its immediate (closest strict) dominator. A node's *level* is its depth in that tree. `SubTree(x)` is x and everything it dominates. The *dominance frontier* DF(x) is every y such that x dominates a predecessor of y but does not strictly dominate y. For a set S, DF(S) is the union, and the *iterated* dominance frontier IDF(S) is what you get by repeatedly adding DF of what you have until nothing changes. If S is the set of nodes that define something, IDF(S) is where its phis go (Cytron et al.).

**The DJ-graph** (section 3). Same nodes as the CFG, two kinds of edge:

- *D-edges*: the dominator tree edges.
- *J-edges* ("join edges"): every CFG edge x to y where x does not strictly dominate y. (A footnote gives the easier reading: mark each CFG edge whose source is the destination's immediate dominator; the unmarked ones are the J-edges.)

Building it takes linear time once the dominator tree exists, and it has fewer than (nodes + CFG edges) edges.

**Two facts about levels.**

- If y is in DF(x), then y's level is no deeper than x's. So to find x's frontier you never look at nodes deeper than x.
- *Lemma 3.1.* z is in DF(x) exactly when some y in `SubTree(x)` has a J-edge y to z and `z.level <= x.level`.

That gives **Algorithm 3.1** for one node: walk `SubTree(x)`; every J-edge leaving it that lands at x's level or above points at a frontier node. (Paper's example: `SubTree(3)` has J-edges to 12, 12, 3, 15 and 12; only 3 and 15 pass the level test; DF(3) = {3, 15}.)

**Why order matters.** Doing that for each node separately re-walks subtrees: computing DF(9) and DF(12) separately visits `SubTree(12)` twice. If DF(12) is done *first* and node 12 marked, the walk for DF(9) can skip everything under 12. So: process deeper nodes first, mark what has been walked, never walk it again.

**Worked example** (mine, small enough to check by hand).

```perl
my $i = 0;            # B1
while ($i < 10) {     # B2
    $i++;             # B3
}
print $i;             # B4
```

Dominator tree: B1 (level 0), B2 (level 1), B3 and B4 (level 2). The only CFG edge whose source does not strictly dominate its destination is the back edge B3 to B2: one J-edge. `$i` is defined in B1 and B3. Take the deepest, B3. Its successor B2 is reached by a J-edge and `B2.level (1) <= B3.level (2)`, so B2 goes into the answer and, not being an original defining node, into the PiggyBank. Next the deepest remaining is B2: its D-edge children are B3 (already visited, skipped) and B4 (visited now, no J-edges). B1 adds nothing. Answer: one phi, at B2.

## Construction / algorithm

**Inputs.** The DJ-graph (so: CFG plus dominator tree plus levels) and the initial set of defining nodes, which the paper calls N-alpha.

**State.** Per node: `visited`, `alpha` (is it in the initial set), `inphi` (already in the answer), `level`. The *PiggyBank* is an array indexed by level, each slot a linked list of nodes waiting to be processed. `CurrentLevel` starts at the deepest level. `CurrentRoot` is the node whose subtree is being walked.

**Algorithm 4.1**, transcribed:

```
Main:
    for each x in initial set:  x.alpha = Alpha;  InsertNode(x)
    while (x = GetNode()) is not NULL:
        CurrentRoot = x
        x.visited = Visited
        Visit(x)

Visit(x):
    for each successor y of x in the DJ-graph:
        if x -> y is a J-edge:
            if y.level <= CurrentRoot.level:
                if y is not already InPhi:
                    mark y InPhi;  add y to IDF
                    if y is not Alpha:  InsertNode(y)
        else (x -> y is a D-edge):
            if y is not Visited:
                mark y Visited;  Visit(y)

InsertNode(x):  push x on the list at PiggyBank[x.level]
GetNode():      pop a node from the deepest non-empty level at or above CurrentLevel
                (updating CurrentLevel), or return NULL
```

In words: walk down the dominator subtree of the current root along D-edges, never re-entering a visited node; at each node "peek" along its J-edges without marking the far end; a far end at the root's level or shallower is a phi node, and if new it is banked for its own turn.

**Paper's trace** (Figure 2 graph, initial set {5, 13}): 13 is at level 5, so it goes first. Its J-edges reach 3 and 15 (both level 2): both join the answer and the bank. Its D-edge child 14 is visited; 14's J-edge reaches 12 (level 4): added and banked. Then 12 (its only successor 13 is already visited), then 5, and so on. The partial trace in Figure 3 ends with the answer set {15, 3, 12, 8, 2}.

**Correctness** (section 5.1; proofs are in a technical report). Lemma 5.1: nothing is ever banked deeper than `CurrentLevel`. Lemma 5.2: deeper nodes are always visited before shallower ones. Lemma 5.3: when `Visit(x)` returns, all of `SubTree(x)` is marked. Lemma 5.4: when it returns, all of DF(x) is in the answer. Theorem 5.1 follows.

**Complexity** (section 5.2). Each node is visited at most once (Lemma 5.5), so each DJ-graph edge is examined at most once: O(E), Theorem 5.2. Banking is O(1) per insert, and `CurrentLevel` only ever decreases, so all the `GetNode` scanning together is O(N). Section 5.3 stresses that the PiggyBank is what makes it linear: with a plain list, stack or queue, either correctness or the bound is lost. For full SSA the cost is O(E times V) for V variables, one run per variable.

**Measurements** (section 6). Implemented in the Parafrase2 compiler; 46 Fortran routines from Perfect, Eispack, Lapack, Ode, Opt and Gator, chosen for being large with unstructured control flow; 15 to 30 percent of nodes chosen at random as the initial set. Against Cytron's method with dominance frontiers stored as linked lists: 2.2 to 8.9 times faster, average about 5.5 (Cytron's time excludes precomputing the frontiers). Against a bit-vector version: 4.2 to 19.8 times, average about 9. Under about 75 nodes both take negligible time. On *ladder graphs* (two rails with rungs, the standard worst case, Figure 4) the old method is quadratic and measured in seconds, the new one linear and in milliseconds; the same trend holds for nested `repeat-until` loops.

The paper covers *placement* only. Renaming is unchanged from Cytron et al.

## Memory, arrays, aliasing

Not addressed. The paper is about graph structure: which nodes need a merge, given a set of nodes that define something. It is framed in terms of *sparse evaluation graphs* (SEGs), a generalisation in which "defines something" means "changes the dataflow information", so it is indifferent to whether the something is a scalar, an array or the heap.

## Relevance to chalk / B::SoN

- **Probably not needed for construction (my judgement).** B::SoN builds its graph while walking perl's op tree, where join points are known from the syntax (see Brandis and Mössenböck). A batch "here is a finished CFG and a set of defining nodes, place the phis" phase does not arise.
- **One memory variable, many writers (my inference).** If chalk ever needs to *re-place* memory Phis after the fact (to repair graphs where writes were left off the chain, or when escape analysis later splits one memory chain into several), the question is "given the blocks that write, where are the merges?", with V equal to 1 and a large initial set. That is one O(E) run of Algorithm 4.1, and the pseudocode above is a few dozen lines of Perl (my estimate).
- **Lemma 3.1 as a checker (my inference).** It gives a direct, table-free test of "does this block need a Phi for a definition in x": is there a J-edge out of x's dominator subtree landing at x's level or above. Useful for asserting that a memory Phi exists where a write requires one.
- **Levels are worth keeping anyway.** Scheduling floating nodes in a sea-of-nodes graph uses the dominator tree and node depths (my inference from Click-style designs), so this algorithm's inputs would already exist.
- **Test shapes.** Nested bottom-tested loops (`do {} while`) and ladder-like graphs are the cases where dominance-frontier methods degrade; the paper says so for nested `repeat-until`. Worth having in any scaling test.
- **Does not apply to:** typing, the memory model itself, lowering to LLVM.

## Limits and later work

Placement only; requires the dominator tree up front; proofs are deferred to a technical report. Related work (section 7): Cytron and Ferrante's almost-linear algorithm, O(E times alpha(E)), reported as never implemented; Johnson and Pingali's dependence flow graph, which yields SSA in O(E times V) but cannot compute an iterated dominance frontier for an arbitrary node set; Johnson, Pearson and Pingali's quick propagation graphs, linear to build but denser. The paper notes J-edges correspond to Cytron's "DF-local" relation, and that Algorithm 3.1 differs from Cytron's frontier computation only in using levels. The authors say the same framework gives incremental dominator-tree maintenance and incremental phi update, in companion reports. Choi, Sarkar and Schonberg cite this paper as the linear-time way to place phis when their incremental update inserts definitions at several nodes. Nguyen and Scholz (2007) list it among the "elaborate" algorithms their matrix formulation is meant to cross-check.
