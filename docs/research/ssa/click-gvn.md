# Global Code Motion / Global Value Numbering

**Authors, venue, year.** Cliff Click. ACM SIGPLAN Conference on Programming Language Design and Implementation (PLDI), La Jolla, 1995.  **Source:** https://bernsteinbear.com/assets/img/click-gvn.pdf

*What I read and how: all 12 pages. Pages 1-9 and the prose of 10 from the extracted text (an OCR scan: prose readable, figures scrambled); the experiments page (255) and the results table, Figure 10 (page 256), from the rendered PDF page images, because the OCR had corrupted the numbers. Page 12 is the bibliography.*

## In one paragraph

If instructions are allowed to "float" in a graph without belonging to any basic block, something must eventually decide where each one goes. This paper gives that something: **Global Code Motion (GCM)**, a near-linear-time pass that places every floating instruction into a block using only its dependency edges. It pulls code out of loops and pushes it down into the branch that actually needs it. Because GCM can always repair placement afterwards, **Global Value Numbering (GVN)**, the pass that merges duplicate computations, can be a very simple hash-table walk that pays no attention to where things are. The pair is simpler than, and on the paper's benchmarks slightly better than, the classic partial-redundancy-elimination approach. The paper is where the phrase "a 'sea' of instructions" comes from.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Separate "what is computed" from "where it is computed".** Optimisations that must keep the program in a legal order at every step are complicated. Let them ignore order; fix the order once at the end.

**Dominance, briefly.** Block A *dominates* block B if every path from the start to B passes through A. The *dominator tree* arranges blocks so that each block's parent is its nearest dominator. A value may be used only where its definition dominates the use; "deeper in the tree" means "later, and under more conditions".

**Every instruction has a legal range.** The *earliest* place it can go is the first block where all its inputs are available. The *latest* is the last block that still dominates all of its uses. Any block on the dominator-tree path between those two is legal. Pick the one in the fewest loops; among those, the latest (so it runs on as few paths as possible).

**Pinned instructions.** Some nodes cannot move: `Phi`, branches/jumps, and return/stop belong to a specific block. Instructions that can fault (the paper lists loads, stores, division, calls) keep an explicit control input; they may be placed in their original block or later, never earlier.

Worked example (the paper's running example, Figure 1/6/7):

```
start:  i0 = 0
        a  = read()
loop:   i1 = phi(i0, i2)
        b  = a + 1
        i2 = i1 + b
        c  = i2 * 2
        if (i2 < 10) goto loop
        return c
```

- *Schedule early*: `b = a + 1` depends only on `a`, so it lands in `start` (hoisted out of the loop). All constants land at the very top. `i2`, `c` and the comparison depend on the Phi, so they cannot leave the loop upward.
- *Schedule late*: `c = i2 * 2` is used only by `return`, after the loop. Its latest block is after the loop, which is at loop depth 0, better than depth 1, so the multiply moves out of the loop downward, and the constant `2` follows it. `b` stays before the loop.

Result: the loop body contains only the Phi, one add, one compare and the branch.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** a program in SSA form as a dependency graph (use-to-definition pointers), plus the control-flow graph of blocks. The original instruction order is ignored.

**GCM, five steps:**

1. Build the dominator tree (Lengauer-Tarjan); record each block's depth in it.
2. Find loops; record each block's loop-nesting depth.
3. **Schedule early.** Starting from pinned nodes, walk depth-first over *inputs*. After all inputs of node `i` are placed, put `i` in the block of whichever input is deepest in the dominator tree (start from the root block).
4. **Schedule late.** Starting from pinned nodes, walk depth-first over *uses*. After all users of `i` are placed, compute the lowest common ancestor (LCA) in the dominator tree of the users' blocks. One twist: when the user is a `Phi`, the use counts as happening in the *predecessor block* matching that Phi input, not in the Phi's own block.
5. **Pick the block.** Walk from the LCA up the dominator tree to the early block; keep the block with the smallest loop depth, preferring the lowest one found. Do this as part of step 4, because placing one node changes the latest position of its inputs.

Dominator tree and loop finding are near-linear; LCA is a simple walk up the tree ("in practice a small constant"). Order *within* a block is then determined by the remaining dependency edges.

**A subtlety about undefined variables.** If a variable is assigned on only some paths, there may be no block where an expression's inputs dominate its uses. SSA construction leaves a Phi merging the real value with "undefined" (written ⊤, "top"). GCM relies on that Phi to anchor the schedule, so GVN must *not* simplify `x = phi(x, undefined)` to `x`.

**GVN:** visit every node once in reverse postorder over dependency edges (inputs before users, except around loops). For each node: (1) if it computes a constant, replace it with the constant; (2) if it is an identity on an input (add of zero, a Phi whose inputs are all the same), replace it by that input; (3) otherwise hash (operation, inputs), ignoring input order for commutative operations, and reuse any existing equal node. The table is never reset at block boundaries. One pass, linear; because it does not iterate to a fixed point, a second run occasionally finds more. After GVN the program may be temporarily illegal (a surviving node may not dominate all its new users); GCM repairs it.

**The larger worked example (Section 3.2, Figures 8-9).** A loop taken from Rosen, Wegman and Zadeck with an `if` inside it. Walking in reverse postorder, GVN finds that `a2 := c0` and `d2 := c0` are copies of `c0`; that makes `l2 := d2 * b0` identical to `l1 := c0 * b0`; and the merge `l3 := phi(l1, l2)` becomes an identity on `l1`. At that moment the program is *illegal*: `l1` was computed in one arm of the `if` but is now used after the join. GCM then moves `l1` (and three other loop-invariant computations) out of the loop, which makes it legal again. This is the paper's demonstration that GVN may ignore placement.

**Experiments (Section 4, read from the page images).**

- *Setup.* 52 procedures from a dozen applications, all Fortran except `cplex` (C); `doduc`, `tomcatv`, `matrix300`, `fpppp` are from SPEC89, the rest from the Forsythe-Malcolm-Moler numerical routines. Code is translated to naive ILOC (a virtual assembly language with unlimited registers and one cycle per operation, including loads and stores), optimised, translated to C and run with cycle counters. The author says plainly that this is "an unrealistic machine model", chosen to isolate machine-independent effects.
- *Common steps.* Every run first reshapes the control-flow graph (splits control-dependent edges, adds loop landing pads) and ends with dead code elimination, copy coalescing and removal of empty blocks. Leaving SSA is "a naive translation" that inserts many copies.
- *Baseline.* GCF (Alpern-Wegman-Zadeck global congruence finding, using available-expressions information), PRE (Morel-Renvoise partial redundancy elimination) and CCP (Wegman-Zadeck conditional constant propagation), run once or twice.
- *Results (Figure 10; "speedup" = how much better GVN-GCM is).*

| Comparison | Average of per-routine speedups | Change in total cycles |
|---|---|---|
| GVN-GCM vs GCF-PRE-CCP once | 4.3% | 0.4% |
| GVN-GCM vs GCF-PRE-CCP twice | 2.4% | 0.2% |
| after reassociation, vs once | 5.9% | 1.6% |
| after reassociation, vs twice | 2.2% | 1.1% |

  The spread is wide: from +23.3% (`doduc/debflu`) down to -6.9% (`doduc/saturr`) in the first column; with reassociation from +26.0% to -24.4% (`zeroin`). Roughly eight of the 52 routines get slower in each column, which is the "GCM may lengthen some paths" caveat showing up in practice. Totals are dominated by a few huge routines (`tomcatv` at about 2.5e8 cycles), which is why the total moves much less than the average. Running the baseline twice recovers about half of GVN-GCM's lead; the paper reads this as the baseline's phase-ordering problem (constants found by CCP only help GCF and PRE on the second round), which GVN avoids by folding constants and finding equalities in one pass.
- *Reassociation* (regrouping integer expressions so invariant parts of array-address arithmetic can be hoisted) helps GVN-GCM more than it helps the baseline.

**Conclusions (Section 5).** GCM needs the dominator tree and loop depths, then "two linear-time passes"; GVN is one linear pass; together they give "a net gain over using GCF, PRE and CCP, and are very simple to implement".

**Related work (Section 1.1), briefly.** Classic loop-invariant code motion (Aho, Sethi, Ullman) cannot hoist a variable assigned more than once because it does not use SSA. PRE never lengthens a path, so it refuses to hoist code used on only some paths through a loop; GCM does hoist it. GCM's sinking resembles partial dead code elimination. PRE finds textually equal expressions, GVN finds equal *values*; the sets overlap only partly. Alpern-Wegman-Zadeck find equalities that hold round loops, which bottom-up GVN cannot, but they cannot use algebraic identities or constant folding.

## Memory, arrays, aliasing (what it says, or "not addressed")

One paragraph, but a decisive one: "To be correct, then, all dependence must be explicit. LOADs and STOREs need to be threaded by a memory token or other dependence edge. Faulting instructions keep an explicit control input." Loads, stores, division and calls are named as the instructions that know their original block. There is no treatment of aliasing or arrays. GCM has no memory-specific rule of its own: correct ordering of memory operations comes entirely from those edges being present.

A footnote adds that faulting instructions can be moved *after* their original block, "which only preserves partial correctness" (a fault that would have happened may be delayed or skipped if the result is unused on some path).

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **This is the scheduler T2 needs** (or needs to be sure LLVM is doing for it). If T2 emits LLVM IR block by block, every floating node must be assigned a block; early/late/LCA is the standard way. If chalk instead keeps a control input on every node, it gives up the hoisting and sinking but needs no scheduler. Which of the two B::SoN does today should be an explicit decision.
- **It explains the "write floats off the memory chain" bug class precisely.** GCM is only correct if *all* dependence is in the graph. A write with no memory edge is, to the scheduler, a pure node: it can be hoisted out of a loop, sunk into a branch, merged with a "duplicate" by GVN, or dropped as unused. So the invariant "every memory write is on the chain" is not a nicety; it is the precondition of this algorithm. A verifier that checks it before scheduling is cheap. (Inference from the quoted sentence.)
- **GVN and memory.** Because the memory version is an input, two Loads of the same address hash equal only if they read the same version. That gives safe redundant-load elimination for free. With explicit `Load` nodes this works out of the box; with "effectful nodes as memory versions" each such node needs a hash rule that includes its memory input and must never be merged if it writes. (Inference.)
- **`die` and other faults: pin by control, not by memory.** Division, method calls, dereferences that can die should carry a control input and may not move above it. This is the paper's mechanism for exactly chalk's "keep die ordering separate from memory" question. Heed the footnote: sinking a faulting node below its original block changes when or whether Perl would die, and in Perl that is observable (`eval`, `$@`, `__DIE__` handlers). Safer to treat such nodes as fully pinned. (Inference.)
- **Undefined values.** Perl's `my $x;` yields `undef`, a real value, not "uninitialised"; if B::SoN models it as a constant `undef` node, the ⊤ problem mostly disappears. Where B::SoN does have "no definition on this path", keep the Phi.

## Limits and later work

GCM is a heuristic: hoisting a computation that is only needed on some paths through a loop can lengthen other paths. It never moves anything past a Phi, does not change the control-flow graph, and does not itself remove redundancy. GVN is "bottom-up" and misses equalities that only show up around loops; Click's thesis ("Combining Analyses, Combining Optimizations") gives a stronger optimistic algorithm. Scheduling memory operations so that two memory versions are never live together is covered in the companion paper, not here.
