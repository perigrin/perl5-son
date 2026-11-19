# Practical Improvements to the Construction and Destruction of Static Single Assignment Form

**Authors, venue, year.** Preston Briggs (Tera Computer Company), Keith D. Cooper, Timothy J. Harvey and L. Taylor Simpson (Rice University). The PDF is a preprint with no venue line (its newest self-citation is "June 1997, to appear"); from background knowledge it was published in Software: Practice and Experience, 1998. **Source:** https://bernsteinbear.com/assets/img/briggs-ssa.pdf

*What I read and how: the whole paper (19 pages, sections 1 to 7 and the reference list) from the extracted text. This PDF is born-digital, not a scan: the prose, both tables and all four pseudocode figures (3, 4, 11, 14) are clean, but the font encoding drops every Greek letter and some ligatures ("phi-node" appears as "-node"). The small code diagrams (Figures 8, 10, 12, 13) come out scrambled; I reconstructed them from the prose that describes them and did not render the pages.*

## In one paragraph

Written by people who had used the Cytron et al. algorithm in a research compiler for years, this paper fixes three practical problems. First, a cheap way to avoid most useless phi functions ("semi-pruned" SSA). Second, a faster way to manage the name stacks during renaming. Third, and most important, it shows that the obvious way of getting *out* of SSA (replace each phi with copies in the predecessor blocks) produces wrong code in two situations, the "lost-copy problem" and the "swap problem", and gives a correct algorithm. Its section 2 is also one of the clearest restatements of the standard construction.

## Key ideas

**Background** (section 2). SSA means each name has exactly one definition point and each use refers to exactly one name. A *phi* (`x3 = phi(x1, x2)`) merges the names arriving at a join. The paper names a "maximal" SSA (a phi for every name at every join) to make the point that every real algorithm is the same two steps, place phis then rename, with fewer phis. *Minimal* SSA places phis using only the shape of the control flow graph. A variable is *live* at a point if its value may still be read later; *pruned* SSA runs a full liveness analysis and places a phi only where the variable is live, which is smaller but needs several large sets per block and repeated passes.

**An assumption** (section 2.3). "We assume that names are used in a type-consistent fashion. A name in the original code cannot be used to hold values that have different types, such as an integer along one path and a float along another ... The construction algorithms implicitly assume that they can determine the type of a phi-function from its inputs."

**1. Semi-pruned SSA** (section 3). Many names, especially compiler temporaries, are defined and used inside one basic block and can never need a phi. One forward pass per block finds the *non-local* names, those read in some block before being written in it, and phis are placed only for those.

```
x = ...; ... = x      # x: written then read in one block  -> local, never gets a phi
... = z               # z: read before any write here      -> non-local
```

It still places a phi for a name that crosses a block boundary but is dead at the join; that is the price of not doing full liveness. On SPEC routines the phi count always falls between minimal and pruned (for the largest routine: 73,778 / 11,989 / 9,886), build time is often *lower than either*, and value numbering afterwards runs markedly faster than on minimal form. The paper notes who needs which: constant propagation and dead-code elimination are fine with semi-pruned; a register allocator wants pruned.

**2. Cheaper renaming** (section 4). Renaming keeps a stack of current names per variable. Cytron pushes at every definition and re-walks the block to pop. Here at most one entry is pushed per variable per block (a later definition in the same block overwrites the top, since the earlier entry can never be read again), and a per-block list records which stacks to pop. In Table 2 the saving in pushes ranges from almost nothing on tiny routines to about 70 percent (19,963 down to 5,641 on one routine), commonly a quarter to a half; build time improves slightly on the large routines.

**3. Getting out of SSA correctly** (section 5). The naive rule: for `x3 = phi(x1, x2)` put `x3 = x1` at the end of the first predecessor and `x3 = x2` at the end of the second. Two ingredients break it. *Copy folding* is deleting a copy `v = x` during renaming and using `x` directly (done by pushing `x`'s name on `v`'s stack). A *critical edge* runs from a block with several successors to a block with several predecessors; a copy for that edge fits in neither end. Splitting the edge with a new empty block fixes that, but is not always possible or desirable late in compilation.

- **Lost-copy problem** (copy folding plus an unsplit critical edge). A loop that returns the previous value of a counter:

  ```
  x = 1                         x1 = 1
  loop: y = x                   loop: x2 = phi(x1, x3)
        x = x + 1          =>         x3 = x2 + 1
        if p goto loop                if p goto loop
  return y                      return x2
  ```

  Folding replaced `y` by `x2`. The naive copy `x2 = x3` goes at the bottom of the loop, before the branch, so `return x2` now yields the *latest* value. The fix: notice that the name about to be overwritten is live past that point, save it in a temporary first, and rewrite later uses to the temporary.

- **Swap problem** (copy folding alone). All phis at the top of a block happen *at the same instant*:

  ```perl
  ($a, $b) = ($b, $a) while $p;
  ```

  After folding, the loop header holds `a2 = phi(a1, b2)` and `b2 = phi(b1, a2)`. Naive copies at the bottom give `a2 = b2; b2 = a2`, and both end up equal. Saving every value in a temporary would fix it but could double the copies; the aim is the fewest temporaries. Some cases need none, only the right order (Figure 13).

## Construction / algorithm

**Construction** (Figure 3, the standard algorithm). Build the dominator tree (A dominates B if every path from the start to B passes through A; Lengauer-Tarjan, O(E log N)) and dominance frontiers (the blocks just beyond the region a block dominates). For each variable, place phis in the iterated dominance frontier of its assigning blocks; for semi-pruned form, only for non-local variables (Figure 4: two sets, one pass per block). Rename with one recursive walk of the dominator tree using `Counters` and `Stacks`.

**Destruction.** Two layers.

*Per block, schedule the copies* (Figure 14):

1. Collect every copy `(source, destination)` required by the phis of the block's successors.
2. Put on a worklist each copy whose destination is not the source of another pending copy; those are safe to emit now.
3. Emit from the worklist. After `dest = src`, the value of `src` also lives in `dest`, so later copies read it from there (a `map` table records this). That may free the copy that overwrites `src`; add it to the worklist.
4. If copies remain but the worklist is empty, they form a cycle (the swap). Break it by copying one destination into a fresh temporary, then continue.
5. Before emitting a copy whose destination is live out of the block, first save the destination in a temporary, placed just after the phi that defines it, and push the temporary's name so that later uses are rewritten (the lost-copy guard).

*Across blocks* (Figure 11): run liveness analysis; walk the dominator tree in preorder with a `Stacks` array like the one used for renaming; in each block rewrite uses to any temporary names, call the scheduler, recurse into the children, pop.

Without critical edges the per-block scheduling alone suffices. With them, the liveness analysis and dominator-tree walk are also needed, and they dominate the cost. No new asymptotic bound is claimed: "correctness rather than performance is the issue".

**Design stance** (section 6). Optimisation passes should not have to worry about whether their output can still be translated out of SSA; the translator should cope with whatever it is given.

## Memory, arrays, aliasing

Not addressed. The paper deals with scalar names (in practice the virtual registers of a low-level intermediate code). Nothing on arrays, heap or aliasing.

## Relevance to chalk / B::SoN

- **Section 2.3 is a direct warning for Perl.** The assumption fails for Perl scalars: `$x` may hold an integer on one path and a string on another. So a Phi's type cannot be read off any one input. T1 has to compute the *join* of the input types (the least specific type covering all of them), and typing must be anchored to the declared variable and its definitions. Typing by use, B::SoN's known problem, is the shortcut this assumption would have allowed and Perl does not. (The assumption is the paper's; the application is my inference.)
- **Phis are parallel.** Perl's `($a, $b) = ($b, $a)` is the swap problem in one line. Anything in T1 or T2 that turns Phis, or list assignments, into a sequence of moves must read all sources before writing any destination. If T2 emits LLVM `phi` instructions and lets LLVM leave SSA, chalk inherits LLVM's solution and need not implement Figure 14 (my inference). The hazard returns if chalk ever lowers Phis to stores into stack slots itself.
- **Copy folding is the default in sea of nodes (my inference).** A sea-of-nodes graph has no copy nodes: `my $y = $x` simply makes `$y`'s table entry point at `$x`'s node. That is copy folding, the precondition for both problems. So chalk is always in the situation this paper warns about, and the lost-copy example (`$y = $x; $x++` in a loop, `$y` used after) is a good regression test for whatever leaves SSA.
- **Critical edges.** If T2 ever needs to place code "on an edge", it needs critical-edge splitting. Worth deciding as an invariant early.
- **Semi-pruning is mostly automatic.** Expression temporaries are edges between nodes, never named variables, so they never get Phis. The idea still applies to lexicals: a `my` variable that never crosses a control-flow join needs none (my inference).
- **Memory Phis** are never lowered to copies, since memory is not a register. The destruction algorithm applies to value Phis only (my inference).

## Limits and later work

The paper leaves phi *placement* alone and says its improvements also apply inside the faster placement schemes of Cytron-Ferrante and Sreedhar-Gao. Semi-pruned form still contains some dead phis. The copy-insertion algorithm with unsplit critical edges needs liveness analysis and may add temporaries; when two unrelated copies form a cycle it breaks the cycle at an arbitrary point. The authors report meeting both problems "in real world codes", and credit Cliff Click with first pointing out the swap problem. From background knowledge rather than these texts: later work on leaving SSA, such as Sreedhar et al. and Boissinot et al. (the latter is in the same reading-list directory), reformulates destruction around explicit parallel copies with stronger correctness arguments.
