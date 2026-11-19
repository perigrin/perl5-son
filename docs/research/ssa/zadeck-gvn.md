# Global Value Numbers and Redundant Computations

**Authors, venue, year.** Barry K. Rosen, Mark N. Wegman (IBM T. J. Watson Research Center), F. Kenneth Zadeck (Brown University). Proceedings of the Fifteenth Annual ACM SIGACT-SIGPLAN Symposium on Principles of Programming Languages (POPL), San Diego, January 1988, pages 12-27. **Source:** https://bernsteinbear.com/assets/img/zadeck-gvn.pdf

*What I read and how: all 16 pages, as page images rendered from the PDF at 120 dpi (the extracted text interleaves the two columns and loses the figures). Everything was legible, including the ten step-by-step figures of the running example, the pseudocode overview (Figure 11) and the reference list.*

## In one paragraph

This paper coins the phrase "static single assignment form" and the abbreviation SSA in its own text ("which we will abbreviate to SSA form"), and writes the phi function as an explicit statement. (Appel's column credits SSA jointly to this paper and a companion paper by Alpern, Wegman and Zadeck at the same conference.) Its actual subject is removing redundant computation: finding expressions certain to compute the same value, across a whole procedure, even when they are spelt differently, and moving computations so that partly redundant ones become fully redundant and can be deleted. SSA is the tool that makes that tractable, because once every name is assigned exactly once, "same name" means "same value", so comparing text becomes comparing values. The conclusion credits three things working together: global *ranks*, SSA, and *phi renaming*.

## Key ideas

**Lexical versus value numbering.** Older global methods only matched *lexically identical* expressions (same operator, same operand names). *Value numbering* gives every value a tag; two expressions get the same tag if they apply the same operator to operands with the same tags. It finds more, but had only worked inside straight-line code, because at a join in control flow a variable might hold either of two values.

**SSA removes the obstacle.** Rename so each variable is assigned once in the program text. Where two names for the same variable meet at a join node (a node with two or more incoming edges), insert `V3 = phi(V1, V2)`: V1 if control arrived by the left edge, V2 if by the right. "Static" because a loop may execute one assignment many times while the text contains only one. The paper states the payoff twice: in SSA form "lexically identical expressions always have the same value, no matter where they occur".

**Trivial assignments are assertions.** `A = B` in SSA says the two names are one value. Delete it and replace one name by the other everywhere, including inside phis (replace whichever has fewer uses; each name then loses at most a logarithmic number of times). Two phi rules follow:

- `Vi = phi(Vj, Vj)` becomes `Vi = Vj`;
- `Vi = phi(Vi, Vj)` becomes `Vi = Vj`.

Each new trivial assignment goes back on the worklist, so removals cascade.

**Rank.** Each computation gets a rank, roughly the height of its expression tree: 0 for entry names and constants; for a copy or a phi, the largest operand rank; for a real operator, one more than that. Operands arriving around a loop's back edge, not yet ranked, count as 0. Working rank by rank means operands are settled before their users, which is how one removal exposes the next ("second order effects") without re-running any analysis.

**Phi renaming.** To move `X1 = A3 + C1` upward past `A3 = phi(A1, A2)`, make one copy per incoming edge and substitute that edge's operand: `X2 = A1 + C1` on the left, `X3 = A2 + C1` on the right. Each copy can now be compared, by text, with what is already on its own path.

**Worked example** (mine, small):

```perl
$x = $a * $b;
if ($c) { $d = $a } else { $d = $a }
$y = $d * $b;
```

In SSA: `x1 = a1*b1`, `d1 = a1`, `d2 = a1`, `d3 = phi(d1, d2)`, `y1 = d3*b1`. Removing the trivial assignments gives `d3 = phi(a1, a1)`, which becomes `d3 = a1` and is removed in turn. Now `y1 = a1*b1`, textually the same as `x1`'s definition, so `y1` is redundant. The paper's own running example (Figures 1 to 10) does the same on a loop containing an `if`, also hoisting `C*B` out of the loop and removing a partial redundancy on `X+1`.

## Construction / algorithm

Input: a *reducible* control flow graph (every loop has one entry). Three phases (Figure 11).

**Phase 1, preprocess.**

1. *Analyse.* Depth-first search to find back edges, a topological order ignoring them ("topsort"), loop headers, loop bodies and exit edges.
2. *Modify the graph.* Give each loop a *landing pad* (a new block that is the header's only predecessor from outside; a `while` is first turned into a guarded `until` loop by duplicating its test). Split every edge that runs from a block with several successors to a block with several predecessors, so there is somewhere to put code. Add *virtual edges* from a landing pad to the loop's exits, for moving code past a loop without putting it inside.
3. *Translate to SSA.* Six rules define it (an entry name `V0`; a fresh name per assignment; the name reaching an edge; no new name where one name arrives on all edges; a phi where two different names arrive; names keep the original values). The "simple" implementation, credited to Cytron-Lowry-Zadeck, visits nodes in topsort order: **at a loop header insert a phi for every variable**, leaving back-edge operands blank; at other joins insert a phi only where different names arrive; rename at each assignment; at the source of a back edge, fill in the blanks. *Reduced SSA form* additionally merges names an equivalence analysis proves equal (two counters stepped identically in a loop).
4. *Assign ranks.* Each block's code becomes an unordered table, the *local computation table* (LCT), hashed by expression; order is recovered later from ranks.
5. *Remove trivial assignments* and *local redundancies* (identical right-hand sides in one block), the two worklists feeding each other until both are empty.

**Phase 2, per rank, lowest first.** Visit blocks in reverse topsort order (bottom up). Each non-back edge has a *movable computation table* (MCT) of candidates offered upward by its destination.

- *Normal block:* take from the MCTs of its outgoing edges. With one successor, take everything; with two, take a computation only if both successors offer the same right-hand side. Then offer upward every computation of the current rank that is not a phi and whose operands are not computed by a non-phi in the same block, phi-renamed per incoming edge. Moving is copying; the original stays for now.
- *Loop header:* a computation may leave the loop only if *question propagation*, a backward search confined to the loop body, confirms that the loop itself recomputes the same value on every path back to the header. Then a copy goes to the landing pad.
- *Landing pad:* may also pull computations back from all the loop's exits along virtual edges, if their operands are defined at or before the pad.
- *Global elimination:* for each computation of this rank, question propagation over the whole graph asks whether an equivalent computation precedes it on every path from entry. If so, create a new variable, assign it at each of those earlier computations, replace this one by a use of it, restore SSA, and remove the resulting trivial assignments.

**Phase 3, normalise.** Order each block's code by rank; replace each `A = phi(B, C)` with `A = B` at the end of one predecessor and `A = C` at the end of the other; delete empty blocks. Variables can later be merged by graph-colouring register allocation.

**Complexity.** Worst case O(C x N x E) for C computations, N nodes, E edges, which the authors call pessimistic: N stands for possible growth in the number of computations, and E for searches that rarely cover the whole graph. With everything taken as n this is O(n^3), against O(n^4) for the PL.8 compiler's repeated Morel-Renvoise passes.

**Optimality** (section 8). For programs without loops, a theorem (proof sketched): any redundancy left is one of three kinds the algorithm deliberately does not attempt: values that are equal but not built by the same operations on the same operands; cases needing exponential code duplication or unsafe speculation ("crossed paths"); and cases where two unequal computations each make a later one redundant on different paths. With loops, two known misses: code on every path through the loop body that is not at the header, and motion along back edges (which risks infinite regress).

## Memory, arrays, aliasing

Not addressed, by explicit assumption (section 4): "it is assumed that assigning to one variable does not affect the value of any other variable", and statements are simple assignments or branches. The paper acknowledges that "complications like procedure calls or the READ statement ... pose some subtle problems that have given rise to a substantial literature on the analysis of aliasing, side effects, and so on", and gives one characterisation: "READ is like a procedure call that both uses and modifies a file parameter while modifying the parameters representing variables read in." In the example it is simply treated as assignments of distinct unknown constants.

## Relevance to chalk / B::SoN

- **Adopt: trivial-phi removal as a standing rule.** `phi(x, x)` becomes `x`; `v = phi(v, x)` becomes `x`. In a sea-of-nodes graph these are peephole rewrites on Phi nodes, and they apply to memory Phis as much as to value Phis (my inference).
- **Adopt: the loop-header strategy.** "Phi for every variable at the loop header, fill in the back edge when you reach it, delete the useless ones" needs no dominance computation and suits a builder walking perl's op tree. Treating memory as one more variable, it also answers "what is memory at the top of the loop" (my inference).
- **The assumption is the warning.** The whole method rests on "same name, same value". For chalk, two reads of `$a[0]` may be merged only if they name the same memory version. A write that floats off the memory chain leaves a later read naming a stale version, and value numbering will then merge two reads that differ. This is my inference from the paper's stated assumption; the paper does not discuss memory.
- **The `READ` remark** is the model for Perl built-ins and calls with side effects: memory in, memory out, plus new values for whatever they assign.
- **Phase 3 is the naive phi-to-copy lowering** that Briggs et al. later show is unsafe once copies have been folded. Relevant only if chalk lowers Phis itself (my cross-reference).
- **Edge splitting** before moving code to predecessors is the critical-edge rule; worth having as an invariant if T1 or T2 ever places code on edges.
- **Does not apply:** the rank-ordered motion machinery, LCT/MCT tables and question propagation. Click-style designs get value numbering by hashing nodes at creation and get code motion from scheduling (my inference). Reducibility is assumed; Perl's `goto` could break it.

## Limits and later work

Reducible graphs only. The simple SSA construction over-inserts phis at loop headers; the paper notes that Shapiro and Saint's "p-graph" is a precursor and that explicit phis "make it easier to work with". Cytron et al. (1991) give the general construction for arbitrary graphs with the minimum number of phis, and remark that the earlier simple algorithm "sometimes inserts extraneous phi-functions". Brandis and Mössenböck say this paper's single-pass sketch "generates many unnecessary phi-assignments". Aycock and Horspool observe that their two deletion rules are the patterns this paper looks for, used here only as cleanup. The authors themselves flag as open: motion along back edges, and whether moving computations helps or hurts register allocation.
