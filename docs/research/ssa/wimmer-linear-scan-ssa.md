# Linear Scan Register Allocation on SSA Form

**Authors, venue, year.** Christian Wimmer and Michael Franz (University of California, Irvine). International Symposium on Code Generation and Optimization (CGO), Toronto, April 2010, pp. 170-179.  **Source:** https://bernsteinbear.com/assets/img/wimmer-linear-scan-ssa.pdf

*What I read and how: all 10 pages. The supplied .txt mixes the two columns, so I re-extracted the PDF text in reading order (plain `pdftotext`) and read Sections 1-9 from that, including the walk-through of the paper's own example (Section 4.2), the resolution example (Section 6), the evaluation and the related-work section. Figure 9 (the statistics table) I read with a layout-preserving extraction of page 7; the numbers below are from it. Figures 3, 8 (interval diagrams) and 10 (stacked bars) are pictures; I used the prose that describes them and the millisecond totals in Figure 9.*

## In one paragraph

Register allocation decides which of the CPU's few registers holds each value at each moment. "Linear scan" is the fast method used by just-in-time compilers: lay the code out in a line, work out for each value the stretch of that line during which it is needed (its *lifetime interval*), and sweep along once handing out registers. Traditionally Phis were removed before this step. The paper shows that if you keep the program in SSA form until *after* allocation, three things get simpler: lifetime intervals can be built in one backward pass with no iterative analysis; some overlap checks become unnecessary; and removing the Phis folds into a step linear scan already has. Implemented in the Java HotSpot client compiler, the result is less code, faster allocation, and equal or slightly better machine code.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Lifetime interval.** Number the instructions 0, 2, 4, ... in layout order. A value's interval is the set of ranges of those numbers where it must be kept. It may have *holes*: if a value is needed in the `else` branch but not the `then` branch, and `then` is laid out between its definition and `else`, it is not needed during `then`.

**Two SSA facts do the work.** (1) Each value has one definition. (2) That definition dominates every use (every path to a use passes the definition). If the block order puts every block after all blocks that dominate it, the definition is always the *first* position of the interval, and everything else can be found by walking backwards from uses.

**Phis are not instructions here.** All Phis of a block together describe a simultaneous shuffle of values on entry. They get no instruction numbers; a Phi's result interval simply starts at the block's first position. A Phi's *input* is treated as used at the end of the corresponding predecessor block.

Worked example (mine):

```
B1:  0: a = ...
     2: b = ...
     4: if ... goto B3
B2:  6: c = a + 1          # last use of a on this path
     8: goto B4
B3: 10: c' = b * 2
    12: goto B4
B4: 14: x = phi(c, c')
    16: return x
```

Walking backwards: `x` is live from 14 to 16. `c` is used "at the end of B2", so live 6-8; `c'` live 10-12. `a` is defined at 0 and last used at 6: interval [0,6]. `b` is defined at 2 and used at 10, but B2 lies between them in the layout and `b` is not needed there: the algorithm gives `b` two ranges, 2-4 and 10, with a *hole* over B2, during which its register may be lent to something else. If `c`, `c'` and `x` all receive the same register, the Phi needs no move at all.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** low-level IR in SSA form with virtual registers; a linear block order in which (1) all dominators of a block come before it, and (2) all blocks of a loop are contiguous; loop headers and loop-end blocks identified.

**BuildIntervals** (one pass, blocks in *reverse* order, instructions in reverse within a block):

1. `live` := union of the successors' live-in sets, plus, for each Phi in a successor, the operand that comes from this block.
2. For each value in `live`, add the range covering the whole block.
3. For each instruction, backwards: an output shortens its range to start at this instruction and leaves `live`; an input gets a range from block start to this instruction and joins `live`.
4. Remove each Phi's output from `live`.
5. **If the block is a loop header:** every value still in `live` is needed throughout the loop, so extend it from the header to the end of the loop's last block. (When the loop-end block was processed earlier, the header's live-in was not yet known; this step patches that, and requirement (2) makes one range sufficient.)
6. Save `live` as this block's live-in.

No fixed-point dataflow iteration is needed. The paper notes the same routine can build an interference graph for graph-colouring allocators.

**The paper's own example (Sections 3 and 4.2).** A factorial loop over blocks B1-B4 with virtual registers R10-R15: R10 is a long-lived, rarely used value (think `this`); R12 and R13 are the loop's two Phis; R14 and R15 the values fed back. Processing order is B4, B3, B2, B1. At B3 the loop header B2 has not been seen, so only the Phi inputs R14, R15 are known live at B3's end; R10 is missed. When B2 (the header) is processed, R10 is found live at its start, so one range from the start of B2 to the end of B3 is added: the loop-header rule in action. Compared with removing Phis first, the Phi intervals now have a single definition point and fewer holes, and the allocator is free to pick which Phi to spill when registers are short, because no artificial order of moves has been imposed.

**No coalescing; hints instead.** Neither version merges intervals (too slow without SSA; not allowed with SSA, since the merged thing would have two definitions). A Phi's inputs and output are linked by *register hints*, which the allocator honours when it can. In the small example the hints remove every move.

**During allocation (Section 5).** Linear scan keeps intervals in four sets: not yet started, *active* (in a register now), *inactive* (started, but in a hole right now), finished. Choosing a register normally means testing the new interval against every inactive one, a step that is not bounded by the number of registers. With SSA intervals that test is unnecessary: an inactive interval started earlier, so the new one is not live at *its* definition, and it is in a hole at the *new* one's definition; two SSA values that never overlap at either definition never overlap at all. The catch: splitting an interval breaks the single-definition property, so the test must still be done for intervals produced by a split. On the Java benchmarks this saves 59% to 79% of intersection tests, though with "no measurable speedup".

**Resolution = SSA deconstruction (Section 6, Figure 7).** Linear scan may split an interval (value in a register here, on the stack there) and already has a *resolution* phase: for every control-flow edge and every interval live at the start of the successor, compare its location at the end of the predecessor with its location at the start of the successor, and insert a move if they differ. A Phi fits the same loop with three extra steps: an interval that *starts* exactly at the successor's first position must be a Phi; fetch that Phi's input for this predecessor; use *that* interval's location as the source (constants are used directly). All moves for one edge form a parallel copy and are ordered by the code that already existed. A new wrinkle: a Phi's source and target may both be stack slots; stack-to-stack moves need a scratch register (almost always free, and a floating-point register will do) or a push/pop, so the allocator tries to give a Phi's source and target the same stack slot.

**Irreducible loops (Section 4.3).** With two entry blocks, a value flowing in through one entry is not seen as live in the other part of the loop. Two remedies: a precise loop analysis that knows all entries; or ensure nothing flows into such a loop without a Phi. The authors use the second, because HotSpot's client compiler builds SSA conservatively and does not prune Phis in irreducible loops. Such loops arise in practice from on-stack replacement (jumping from the interpreter into the middle of a running loop).

**The same pass builds an interference graph (Section 4.4).** At each definition, the defined value conflicts with everything currently live; at a loop header, everything live there conflicts with everything defined in the loop.

**Evaluation (Section 7; Figure 9).** HotSpot client compiler from an early JDK 7 snapshot, x86, 2.33 GHz Xeon; averages of 20 runs. Baseline = product version (Phis removed before allocation).

| | SPECjvm2008 | SPECjbb2005 | DaCapo | SciMark |
|---|---|---|---|---|
| Methods compiled | about 6,800 | about 520 | 8,242 | 23 |
| Total compile time | -4% | -4% | -5% | -8% |
| Back-end time | -13% | -13% | -16% | -19% |
| Memory for lifetime analysis | -10% | -10% | -24% | -9% |
| Moves before allocation | -11% | -14% | -12% | -35% |
| Register-to-stack moves after | -13% | -17% | -14% | -5% |
| Machine code size | -0% | -1% | -0% | -1% |

By phase (Figure 10, from the text): building the low-level IR 19-27% faster (no Phi removal there); lifetime analysis 25-31% faster (no dataflow iteration); the scan itself unchanged, except 13% faster on SciMark where loops are dense; resolution 1-10% slower (it now removes Phis). Two new kinds of move appear, constant-to-stack and stack-to-stack (for example 926 and 294 on SPECjvm2008, against about 5,000 fewer register-to-stack moves), because a Phi may be given a stack slot right at its definition; overall there are fewer moves. Run time of the generated code is unchanged within noise, except a 1% gain on SciMark's FFT. Source size: about 180 lines of Phi-removal and 150 lines of dataflow code deleted, about 120 added; net about 200 lines shorter.

**Related work (Section 8).** Poletto and Sarkar's original linear scan has no holes or splitting; Traub et al. added both; Mössenböck and Pfeiffer's earlier "linear scan on SSA" still inserted the moves first and used dataflow analysis; graph-colouring allocators on SSA (Hack et al., in libFIRM) exploit the same dominance facts to separate spilling from colouring; Boissinot et al.'s fast liveness check answers single queries and is not suited to building whole intervals; and the hard cases in Boissinot et al.'s out-of-SSA paper arise only when critical edges cannot be split, which is always possible for Java bytecode.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed. The paper is about virtual registers after instruction selection. Stack slots appear only as spill locations.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Does not apply to the current pipeline.** T2 emits LLVM IR; LLVM does register allocation and Phi elimination. Nothing here should be built now.
- **Relevant if chalk grows its own backend** (a baseline JIT, a bytecode with registers). Then this is the simplest serious allocator to start from, and its prerequisites tell you what the scheduler must deliver: a linear block order with dominators first and loops contiguous. Click's Global Code Motion already computes the dominator tree and loop nesting this needs. (Inference.)
- **A way to think about the memory chain.** Click's paper says the scheduler should treat memory "like a type of unique machine register with infinite spill cost". In this paper's terms: the lifetime intervals of successive memory versions must never overlap, i.e. every read of version N must be laid out before the write that creates N+1. BuildIntervals run over only the memory values would be a cheap checker that T2's instruction order respects the chain. (Inference.)

## Limits and later work

Evaluated only in the HotSpot client compiler on Java benchmarks. Needs special block ordering; loops with several entry points (irreducible, rare in Java) break the loop-header step and need extra loop analysis. Does not attempt the "spill everything first, then colour" approach that SSA's structure also permits. Rogers, "Efficient global register allocation" (arXiv 2011.05608) goes a step further and tries to avoid building intervals altogether.
