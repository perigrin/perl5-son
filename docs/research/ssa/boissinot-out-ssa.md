# Revisiting Out-of-SSA Translation for Correctness, Code Quality, and Efficiency

**Authors, venue, year.** Benoit Boissinot, Alain Darte, Fabrice Rastello (ENS Lyon / Inria), Benoît Dupont de Dinechin, Christophe Guillon (STMicroelectronics). LIP Research Report RR2008-40, 2008 (the copy summarised here; HAL inria-00349925). Published at CGO 2009 (my addition; not stated in the extracted text).  **Source:** https://bernsteinbear.com/assets/img/boissinot-out-ssa.pdf

*What I read and how: all 15 pages. The supplied .txt interleaves the two columns line by line and is not reliably readable, so I re-extracted the text from the PDF in reading order (plain `pdftotext`, saved in my scratch directory) and read Sections I-V in full from that, including Lemma 1 with its proof and the descriptions of Algorithms 1-2. The bar charts (Figure 5 on page 10, Figures 6-7 on page 13) I read from rendered page images; bar heights quoted below are read off the charts by eye and are approximate. The pseudocode listings lost their line structure in both extractions; I describe them from the prose that explains them. Page 1 is a repository cover sheet; pages 14-15 are conclusion and references.*

## In one paragraph

SSA has Phi nodes; real machines do not. "Going out of SSA" means replacing each Phi with ordinary copy instructions. Straight after SSA construction this is trivial, but after optimisations such as copy propagation it becomes subtly wrong if done naively, and earlier fixes were either patches for known bad cases or correct but slow. This paper gives a clean recipe that separates the two concerns. **Correctness**: first insert copies everywhere they could possibly be needed, treating all the Phis of a block as one simultaneous "parallel copy". **Quality**: then delete as many of those copies as possible by *coalescing* (merging two variables into one when they never hold different live values at the same time). A sharper definition of "these two variables conflict" removes more copies, and new algorithms make the whole thing about 2x faster and 10x smaller in memory than the best previous method (Sreedhar et al.'s Method III) on SPEC CINT2000.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Why naive is wrong.** The textbook rule (Cytron et al.) is "for `x = phi(a, b)`, put `x = a` at the end of the first predecessor and `x = b` at the end of the second". Briggs et al. found two classic failures and patched them; Sreedhar et al. gave the first method that is both simple and correct.

*Swap problem.* All Phis at the top of a block happen at once. After copy propagation a loop that swaps two variables looks like:

```
loop:  a2 = phi(a1, b2)
       b2 = phi(b1, a2)
```

On the back edge that means "a2 and b2 exchange values". Copies done one after another (`a2 = b2; b2 = a2`) destroy one of them. The pair is a *parallel copy* `(a2, b2) = (b2, a2)` (read everything, then write everything) and costs one temporary.

*Lost-copy problem.* If the copy for a Phi lands at the end of a block that also branches somewhere else (a *critical edge*: from a block with several successors to a block with several predecessors), the copy overwrites a value the other successor still needs.

**Conventional SSA (CSSA).** SSA in which all variables connected through Phis can safely share one name. Fresh SSA is conventional; optimised SSA often is not. Leaving CSSA is trivial, so the real job is "make it conventional again, cheaply".

**The trick that guarantees correctness (Sreedhar's Method I, Lemma 1).** For `a0 = phi(a1, ..., an)`, introduce fresh `a0', a1', ..., an'`; put `ai' = ai` at the end of predecessor i; put `a0 = a0'` right after the Phis; make the Phi `a0' = phi(a1', ..., an')`. Proof idea: each primed variable lives for an instant, at the very end of a different block or the very start of the Phi's block, so no two are ever alive together and they can share a name. The paper points out this is exactly what Cytron's rule lacked: without the extra copy at the *top* of the block, `a0` itself can live long enough to collide.

**Two traps the paper says nobody had written down.**
1. Copies cannot always go at the very end of a block: they go *before* the branch instruction. If the branch reads a variable `u`, the new copy is alive while `u` is still needed, so the collision test must include `u`, not just what is live out of the block. Sreedhar's Method III misses this and can produce wrong code (Figure 1).
2. Some branch instructions *define* a variable (a "branch and decrement" loop instruction on DSP-style processors). No copy can be placed after that definition and before the jump. If that variable feeds a Phi and collides with the Phi's result, copy insertion alone cannot work; the edge must be split or the instruction changed (Figure 2).

**Then it is "just" coalescing.** Once in CSSA, every copy is an ordinary copy, and removing copies is the well-known *aggressive coalescing* problem from register allocation (merge the two ends of a copy when they do not conflict; NP-complete in general, good heuristics exist). No SSA-specific rules are needed. Correctness (step 1) and quality (coalescing) are separated.

**Value-based interference.** The usual tests: "their live ranges intersect", or Chaitin's "one is live where the other is defined, unless that definition is a copy between them". The paper's test: *live ranges intersect and the values differ*. In SSA each variable has one definition, so one value, and "same value" is cheap: walk the dominator tree, and for a copy `b = a` set V(b) = V(a), otherwise V(b) = b. Example: after `b = a; c = a`, all three have value `a` and none conflict, whereas Chaitin's test says `b` and `c` conflict. A bonus: with this definition merged groups never need their conflicts recomputed.

**Worked examples in the paper.** *Swap* (Figure 3): after inserting primed copies and coalescing, exactly one swap remains, emitted as three copies with a temporary. *Lost copy* (Figure 4): one copy on the back edge genuinely cannot be removed; all others are. Splitting the back edge gives a different, equally valid result.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** SSA code in which definitions dominate uses; a dominator tree; liveness information (sets, or a "is `v` live here?" oracle); optionally block execution frequencies.

**Four phases.**

1. **Insert parallel copies** for every Phi as above; merge all primed variables of a Phi into one group ("congruence class").
2. **Compute interference** using intersection plus the value test.
3. **Coalesce aggressively**, heaviest (most frequently executed) copies first. Extras:
   - *Copy sharing.* If `b` and `c` are both copies of `a` and their live ranges intersect, merge `b` and `c` even when neither can merge with `a`: one copy does the work of two.
   - *Register constraints* (calling conventions, dedicated registers): split the variable's live range with parallel copies right around the constrained instruction, then let coalescing clean up; groups tied to different machine registers are declared conflicting.
4. **Sequentialise** each remaining parallel copy (Algorithm 1; the authors note C. May had published a similar algorithm). Picture the copies as arrows `a -> b`. Each variable has at most one incoming arrow, so the picture is a set of rings, each ring possibly with trees hanging off it. Emit tree copies from the leaves inward (copy a value onward before overwriting it). For a ring: if some ring member was already copied into a tree, that copy serves as the spare; otherwise copy one member into a fresh temporary; then go round the ring. Example from the paper: `(a->b, b->c, c->a, c->d)` becomes `d = c; c = a; a = b; b = d`, with no temporary because `d` holds the spare. The number of copies is minimal: one extra per ring that has no tree.

**Making it fast (Section IV).**
- *Intersection tests.* Three options surveyed: classic live-in/live-out sets plus an interference bit-matrix; Budimlić et al.'s test ("the variable whose definition dominates the other's is live at that second definition"), which needs liveness sets but no matrix; and Boissinot et al.'s fast liveness check, which needs neither and survives code edits because it depends only on the control-flow graph.
- *Linear test between two merged groups (Algorithm 2).* Keep each group as a list sorted by depth-first order of the dominator tree. Sweep both lists together with a stack that mimics walking the "dominance forest" (each variable's parent is the nearest group member whose definition dominates it). It suffices to test each variable against its parent, so the number of tests is linear in the group sizes instead of quadratic. With the value test this needs one more pointer per variable, its nearest "equal intersecting ancestor", so that same-valued neighbours are skipped correctly.
- *Virtualisation.* Do not materialise primed variables and copies up front; pretend they exist, process one Phi at a time, and create a copy only when it turns out it cannot be merged away.

**Experiments.** SPEC CINT2000 (minus the C++ benchmark `eon`), compiled by STMicroelectronics' Open64-based ST200 compiler feeding their JIT compiler for CLI.

*Quality (Figure 5): remaining copies relative to the crudest test ("Intersect" = 1.0), summed over the suite, read from the chart.* Sreedhar's Method I coalescing about 0.90; Chaitin's test about 0.81; the value test about 0.76; Sreedhar's Method III about 0.77; value test plus an independent-set search about 0.74; plus copy sharing about 0.72. Per benchmark the best variant ranges from about 0.46 (`gzip`) to about 0.90 (`vortex`). The ordering is the paper's point: each sharper notion of conflict removes more copies, and the simple scheme with the value test beats the intricate Method III.

*Speed (Figure 6), relative to Sreedhar III = 1.0.* Dropping the interference matrix alone ("InterCheck") makes things slower (about 1.4 over the suite); adding the fast liveness check and the linear group test brings both the virtualised and the non-virtualised variants to about 0.5. The paper's words: "about twice faster". Notably the simple non-virtualised version is as fast as the virtualised one.

*Memory (Figure 7).* The gain comes almost entirely from not building the interference graph; the recommended variant (no virtualisation, linear test, no graph, liveness checking) uses "about 10 times" less than Sreedhar III. The authors add that their accounting favours the classic approach, because memory used while *constructing* liveness sets was not counted.

**Conclusion (Section V).** The recommended configuration is the simplest one: insert all copies, coalesce with value-based interference using the linear group test and liveness checking, sequentialise. The authors rate Sreedhar's Method III "hard to implement correctly" with branches that use or define variables, and Budimlić et al.'s method as unable to handle critical edges.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed. "Memory" in this paper means the compiler's own memory footprint. The subject is scalar SSA variables only.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Mostly does not apply today.** T2 lowers to LLVM IR, which keeps Phis; LLVM performs out-of-SSA translation and coalescing itself. Chalk should not implement this.
- **What it does teach, and chalk needs now: Phis of one join are simultaneous.** Any place that *interprets* Phis one after another (an IR interpreter used for testing B::SoN, a constant folder, T1 evaluating a `Region`'s Phis) must read all inputs before writing any output, or a swap such as `($a, $b) = ($b, $a)` in a loop is silently mis-evaluated. (Inference.)
- **The memory Phi is a Phi like any other.** If chalk ever lowers the memory chain to something physical (it normally just disappears into LLVM's implicit memory), the same parallel-copy reasoning applies. More practically: when T2 erases memory edges, the ordering they implied must already be fixed in the emitted instruction order. (Inference.)
- **Critical edges.** If T2 ever needs to place code "on an edge" (for example a conversion needed for only one Phi input), split the edge first. Perl's `last`/`next` inside conditionals produce such edges readily.

## Limits and later work

Requires dominance-based SSA and assumes copies can be placed on all edges (some branch instructions that also define variables need special handling, which the paper discusses). Results are for one industrial compiler (STMicroelectronics') on SPEC CINT2000. The Cornell CS 6120 SSA lesson recommends this paper as the reference for doing out-of-SSA properly. The alternative of allocating registers first and removing Phis afterwards is in Wimmer and Franz, "Linear Scan Register Allocation on SSA Form".
