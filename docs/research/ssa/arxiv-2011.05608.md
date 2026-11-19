# Efficient Global Register Allocation

**Authors, venue, year.** Ian Rogers (Google). arXiv preprint 2011.05608v1, 11 November 2020 (not peer-reviewed as far as the source shows).  **Source:** https://arxiv.org/abs/2011.05608

*What I read and how: all 12 pages. The supplied .txt mixes columns in places, so I re-extracted the PDF text in reading order (plain `pdftotext`) and read Sections 1-7 from that: target machine, compiler, the allocator (Algorithms 1-6 and the heuristics), the measurements, the proposed improvements, related work and conclusions. The pseudocode listings lose some lines in extraction; I describe them from the explanatory prose. Figures 1-5 are charts; the percentages below are the ones the text states.*

## In one paragraph

Register allocation assigns each computed value to one of a limited set of machine (or virtual-machine) registers so that no register holds two needed values at once. The two classic methods first build a big side table of "who conflicts with whom": graph colouring builds an *interference graph*; linear scan builds a *lifetime interval* per value. Rogers observes that these tables can cost as much memory as the program representation itself and a noticeable share of allocation time, and proposes a scan-style allocator that builds neither. It walks the instructions in final layout order, keeps a set of values currently in registers (*active*), and adds one new set, *future-active*, for values that already own a register but are not needed right now. Only when a candidate register is tied up in future-active does it run a small on-the-spot check, "are these two values live at the same time?". In the production compiler studied (Java bytecode to Android dex files), that check was never needed for about 80% of methods, and over 90% of live ranges were trivial.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Vocabulary.** A value is *live* from where it is computed until its last use. A *liveness hole* is a stretch in the middle of that span where the value is not needed (for instance during the other arm of an `if`). In this paper "instruction" and "value" are the same thing, as in any SSA IR.

**Plain linear scan** (Poletto and Sarkar): sort intervals by start; at each start, free the registers of intervals that have ended ("expire"), then take a free register.

**The change.** Do not precompute intervals. Walk blocks, and instructions within blocks, in order. At instruction `i`:

1. For each input `j` of `i`: if this is `j`'s last use, free its register. If `j` has later uses but not right away (a hole), *pause* it: move it from `active` to `future-active`, remembering its register.
2. Allocate a register for `i`. If `i` is already in `future-active` (for example it was pre-assigned), reactivate it. Otherwise choose the cheapest register such that `i` is not live at the same time as any future-active value holding that register.

Worked example (mine):

```
v1 = ...            # gets r0
if c:
    v2 = f()        # v1 not used in this arm: r0 may be lent to v2
    use(v2)
else:
    use(v1)
```

Entering the `then` arm, `v1` is live out of the earlier block but not live in this one, so it is paused: `future-active = {v1: r0}`. When `v2` needs a register the allocator asks whether `v1` and `v2` are ever live together. They are not (`v2` dies inside the arm, `v1` is only needed in the other arm), so `v2` may borrow `r0`.

**The "live at the same time" test** (Algorithm 5) uses only per-block live-in/live-out sets plus a backward scan of one block; its cost is bounded by the number of instructions in a block.

**Phis.** A Phi and the copies that feed it from the predecessor blocks are pre-allocated together and placed in `future-active` before the main loop, which steers them into one register so the copies disappear (register *coalescing*).

**When allocation fails.** No spilling to memory in the usual sense. Either increase the register count (dex allows up to 65,536 virtual registers, but short instruction encodings reach only the first 16 or 256), or split one live range by inserting a move, and restart the allocator. Because there is no interval table, there is nothing to patch up before restarting.

## Construction / algorithm (steps, complexity, inputs it needs)

**Why it matters to the author (Sections 1-2).** In LLVM compiling itself, building live intervals is not the slowest register-allocation phase but still about 20% of one of its major portions (0.2% of whole compile time). The target here is Android's *dex* bytecode, which has up to 65,536 virtual registers but awkward encodings: every instruction can name registers 0-15, fewer can name 16-255, very few beyond; 64-bit values need two adjacent registers; calls with many arguments need a consecutive run; parameters arrive in the highest-numbered registers. Other dex compilers allocate first and then repair illegal assignments with extra moves ("in simple cases a third of instructions in the final code"); this allocator assigns final registers directly and retries on failure. The goal is small code, not a small register count.

**The compiler around it (Section 2.2).** SSA is built with predecessors processed first; loop back-edges and exception handlers get Phis for everything, pruned afterwards. The middle end runs dataflow over a lattice of constants, types, nullness and *integer ranges*, solved with Bourdoncle's iteration order, and type information "is held within the instruction" (one `add`, not `int-add`, `long-add`, ...). Because many Java instructions can throw, blocks are split at throwing instructions when instruction-level dominance is needed ("unfactoring"), except where type analysis proves no exception is possible.

**Preparation (Section 3.1).** Unfactor within try-regions; move instructions close to their uses ("shrink live range"); duplicate constants near their uses unless they have three or more register uses; compute per-block live-in/live-out sets by a fixed point (Phi inputs are added to the predecessors' live-out sets first, so a Phi does not make all its inputs live on all predecessors); split critical edges and put parallel-copy blocks ("Phi-moves") in predecessors; add a "swap-move" where a temporary is needed. Many critical edges come from exception handlers.

**Main loop (Algorithm 2).** For each block in final code-layout order: values live out of the previous point but not live into this block are expired, or *paused* into `future-active` if some unvisited block still needs them; values live in but not yet active are started. Then for each instruction, handle its inputs (expire or pause), and allocate its output (Algorithm 4). An instruction is never in both sets. A value may enter a register's `active` or `future-active` set only if it is not live at the same time as anything already there; when both sets are empty, which is the common case, no test is needed.

**The "live at the same time" test (Algorithms 5-6).** Same block: both live out means yes; neither live out means find which is defined first and scan back to see whether it is still used after the other's definition; otherwise the live-out one is the question. Different blocks: is one live into, or through, the other's block. Cost is bounded by the block length, or by the number of uses if positions within a block are known. Only the order *within* a block is needed, not a global numbering.

**Pre-allocation (Section 3.5).** Fixed-register values (in dex only parameters), argument-setup move blocks and spill moves are placed in `future-active` before the main loop, so later choices can see them. This plays the role of "fixed intervals".

**Coalescing and register choice (Sections 3.6-3.7).** Backward: when allocating a move, find the original value behind chains of moves and Phis and reuse a register already holding it. Forward: prefer a register that a future move will want this value in. During emission a move that would copy a value into a register already holding it is dropped. Otherwise cost favours: two-address forms; keeping a debugger-visible variable in its previous register; overwriting registers that hold object references (so objects do not stay reachable longer than needed in the interpreter); even alignment for 64-bit pairs; and low register numbers generally.

**Failure (Section 3.3).** If no legal register exists, either raise the register count or split a live range: free a low register with a pre-allocated "spill-move" to a high one and insert "fill-moves" before the uses that need a low register (one dominating fill, or one per use, whichever is cheaper), then restart. With no interval table there is nothing to patch.

**Measurements (Section 4).** Android Open Source Project, branch android-9.0.0_r9: 693,166 methods; on average 4.85 blocks per method, 7.48 instructions per block, 3.53 registers per method.
- Time: almost half of allocation goes to liveness analysis and pre-allocation; expiring/starting at instructions about 32%; at block boundaries about 6%.
- 80.2% of methods never call the live-at-the-same-time test. The worst-case calls per instruction are under 10 for 90% of methods, under 70 for 99%, under 400 for 99.9%. The author calls the tail "disappointingly large"; the outliers were all large class initialisers full of constants.
- Shape of the code: an instruction is used on average by 0.793 others; 33.8% have no uses, 60.5% are used only in their own block, 59.4% have exactly one use. Hence "over 90% of intervals for instructions are trivial".
- Retries: 81.3% of methods needed none; a further 18.2% only retried to add registers.

**Suggested improvements (Section 5).** Layout order is not chosen to avoid holes (a value used only in an exception handler at the end can sit in `future-active` for the whole method); reverse postorder would help. Walking backwards (uses before definitions) would make "is this the last use?" trivial. A priority queue of instructions, as LLVM's greedy allocator has for intervals, could improve quality. Intervals could be built lazily only where they pay.

**Related work (Section 6).** Poletto and Sarkar's attempt to skip interval construction approximated liveness and could make code 6.8x slower; Treescan (Colombet et al.) also avoids intervals on SSA but cannot look ahead and repairs with moves; the author says Treescan given `future-active` sets would behave like this allocator with a reverse-postorder walk. The coalescing heuristics resemble Wimmer and Mössenböck's register hints. The approach "keeps the intermediate representation and side metadata down to a minimum", likened to sea-of-nodes compilers.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed as a subject. Two passing remarks touch memory ordering: the control-flow graph is "unfactored" only within try-regions "as memory operations will not be reordered", and load/store elimination is mentioned as an earlier pass. One relaxation is noted: the compiler lets a `new` sink down next to its constructor call even though Java says an out-of-memory error should be raised earlier.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **An incidental parallel with T1.** This production compiler keeps type, nullness and integer-range facts on each instruction, uses one generic `add` whose meaning comes from that type, and solves its dataflow with Bourdoncle's ordering. That is the same shape as chalk's T1 (types and integer intervals on nodes), and Bourdoncle's ordering is also what Lemerre's paper uses. (Inference about the parallel.)
- **Exceptions and block structure.** Their rule: split blocks at instructions that may throw only when instruction-level dominance is needed, and skip the split where analysis proves no exception; they explicitly tie this to not reordering throwing instructions with memory operations. Perl has far more potentially dying operations than Java, so the same economy (prove "cannot die", then relax) is relevant to how chalk pins nodes. (Inference.)
- **Does not apply to the current pipeline.** T2 hands LLVM IR to LLVM, which allocates registers. Do not build this.
- **Worth remembering if chalk targets a register-based virtual machine or writes a baseline backend.** The appeal is the same one the paper itself points to when it likens its minimal side-data approach to "sea-of-nodes representations": keep the IR and almost nothing else. The statistic that most live ranges are trivial is likely to hold for straight-line Perl subs too, though that is a guess. (Inference.)
- **A caution relevant to `die` ordering.** The paper's compiler deliberately bends Java's exception-ordering rule for out-of-memory errors to shorten a live range. That is the kind of "harmless" reordering of a faulting operation that chalk has decided to prevent by keeping `die` ordering on its own chain; the example shows how tempting such shortcuts are in a backend. (Inference.)

## Limits and later work

A preprint describing one production compiler; no comparison of generated-code quality against graph colouring or classic linear scan (the author says such comparisons are already in the literature). Still needs global liveness sets. Relies on being able to add registers or restart, which suits a virtual-register target better than a real CPU with a small fixed set. Block traversal order affects how often the expensive path is taken; the paper discusses alternatives (including Treescan-style orders) as future improvement.
