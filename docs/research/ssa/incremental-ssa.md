# Incremental Computation of Static Single Assignment Form

**Authors, venue, year.** Jong-Deok Choi, Vivek Sarkar and Edith Schonberg (IBM T. J. Watson Research Center and IBM Software Solutions Division). The extracted text has no venue line; the page numbers run 223-237 and its newest citation is Sreedhar and Gao's January 1995 paper. From background knowledge it appeared at the International Conference on Compiler Construction (CC '96, Springer LNCS), 1996; the text itself confirms only "1995 or later". **Source:** https://bernsteinbear.com/assets/img/incremental-ssa.pdf

*Extraction note: mostly clean text. Phi symbols are dropped in places and Figures 3 to 5 are lost. I did not read the last two loop transformations (after loop fusion) in detail.*

## In one paragraph

The standard SSA construction is all-or-nothing: change one statement and the textbook answer is to rebuild SSA for the whole procedure. This paper asks what the smallest repair is. It gives exact procedures for four edits (add a use, delete a use, add a definition, delete a definition), proves that the damage from any of them is confined to a known region, extends the idea to "this whole loop was rewritten", and then gives hand-tuned recipes for common loop transformations whose cost depends only on the number of loops, not the size of their bodies.

## Key ideas

**Terms.** Block n *dominates* m if every path from entry to m passes through n. The *dominator tree* hangs each block under its closest dominator. The *dominance frontier* of n is the set of blocks where n's dominance just ends: n dominates a predecessor of the block but not the block itself. Phis for a definition go at its *iterated* dominance frontier (the frontier, the frontier of those, and so on).

**Two properties that define correct SSA** (the paper's Properties 1 and 2):

1. An ordinary use of `X_i` is dominated by the definition of `X_i`, with no other definition of the same variable in between on the dominator tree.
2. A use of `X_i` as a phi operand sits at the dominance frontier of `X_i`'s definition, and `X_i` is the version reaching the end of the corresponding predecessor.

**Reaching definition.** For a statement S and variable v, `reaching_def(S, v)` is the one version of v visible at S. You find it by walking *up the dominator tree* from S until you meet a definition of v.

**Locality theorem.** If a definition of v is inserted or deleted at S, and r is the definition that reaches S, then every statement that has to change is either dominated by r or in r's iterated dominance frontier. Nothing else in the program is touched.

**Redundant phi.** A phi is redundant if all its operands, other than references to itself, are the same name: `X_i = phi(X_j, X_j)` or `X_i = phi(X_i, X_j)`.

**Worked example** (the paper's Figure 2):

```
S1:  X1 = ...
S2:  if ...
S3:     repeat
S4:        X2 = phi(X1, X3)
S5:        X3 = ...            <- delete this
S6:     until ...
S7:  X4 = phi(X1, X3)
S9:  ... X4 ...
```

Delete S5. Uses of `X3` become uses of the definition that reached S5, which is `X2`. Now S4 reads `X2 = phi(X1, X2)`: redundant, so delete it and replace `X2` by `X1`. Now S7 reads `X4 = phi(X1, X1)`: redundant, delete it, and the final use becomes `X1`. Inserting the definition back runs the same film backwards. (I simplified the figure by dropping one more join; the cascade is the same.)

## Construction / algorithm

All four procedures assume the dominator tree and def-use lists (for each definition, the list of its uses).

- **Insert / delete a use at S:** find `r = reaching_def(S, v)`; add or remove the use from r's list. Cost: the height of the dominator tree.
- **Delete a definition d at S:** (1) repoint every use of d, including phi operands, to r; (2) if any phi has become redundant, delete it and repeat with that phi as the deleted definition.
- **Insert a definition d at S:** (1) for each block in the dominance frontier of S that lacks a phi for v, create one, recursively; (2) walk *down* the dominator tree from d and from each new phi, repointing the uses they now reach; (3) fix up the operands of the new phis using Property 2.

Cost of the definition cases: proportional to the region dominated by r plus its iterated dominance frontier. In the worst case that is the whole procedure, but "often much more efficient". The result is minimal SSA when the CFG is *reducible* (every loop has a single entry). For irreducible graphs, deletion needs an extra pass to remove groups of phis that refer only to each other and one outside name.

**Whole-interval update.** An *interval* here is a loop: a header plus the blocks that cycle back to it. The CFG is augmented with a *preheader* before each loop and a *postexit* node per exit. If a loop is rewritten: rebuild dominators and frontiers for that loop only, redo its phis and renaming, touch nested loops only at their *upwards-exposed uses* (uses of a value that comes in from outside), and fix the outside world only if the *set of variables the loop defines* has changed. If it has not (the "conservative change property"), nothing outside moves.

**Loop transformations.** For interchange of rectangular loops, no use list changes at all. For general reordering of n loops into n', delete and recreate the per-loop header and exit phis: O(n^2 + n'^2), independent of body size. Loop fusion is similar; some others (the conclusion names loop distribution) cost time proportional to body size.

## Memory, arrays, aliasing

Not addressed directly. Variables are treated as scalars. The only mention is in related work: Cytron and Gershbein's technique for incrementally adding "may-defs" (definitions caused by possible aliases) on demand, which this paper contrasts with rather than builds on.

## Relevance to chalk / B::SoN

- **"Insert definition" is the repair recipe for the known bug class (my inference).** In chalk's design memory is a single SSA variable. A write that floated off the chain is a definition of memory that was never inserted. The paper's procedure says what putting it back involves: find the memory version reaching the write, make the write consume it, add memory Phis at the write's iterated dominance frontier, then repoint every read and write dominated by the new version. Step 2 is the one a quick fix tends to forget: later reads must move to the new version, not just the next write.
- **The locality theorem bounds what a fix or a checker must look at:** only nodes dominated by the previously reaching memory version, plus its iterated frontier.
- **A verifier falls out of Properties 1 and 2 (my suggestion).** For every read: walk up the dominator tree from the read's control position to the nearest memory definition, and check that it is the version the read names. A floating write shows up as a read naming an older version than the walk finds. In a sea-of-nodes graph this needs memory-affecting nodes to have a definite control position, which they do if writes are pinned to control.
- **Redundant-phi deletion** is the same rule as in Rosen-Wegman-Zadeck and Aycock-Horspool, and should be a standing peephole on value and memory Phis alike.
- **The "set of variables defined" test** is a useful question for any T1 rewrite: if a region still writes memory after the rewrite, nothing outside it needs new Phis.
- **Does not apply:** the loop interchange, fusion and reordering recipes target Fortran-style `do` nests. Chalk has no such passes in view.

## Limits and later work

Assumes statement-level positions, an up-to-date dominator tree and reducible control flow for minimality. It handles changes to statements and loops, not arbitrary edits to the CFG's edges (it cites Ryder and Carroll for incremental dominator-tree update). Sreedhar and Gao say their DJ-graph framework also supports incremental phi placement and dominator-tree update, in companion papers. From background knowledge, not from these texts: production compilers later adopted on-demand "SSA updater" utilities that follow the same insert-definition logic.
