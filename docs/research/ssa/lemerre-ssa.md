# SSA Translation Is an Abstract Interpretation

**Authors, venue, year.** Matthieu Lemerre (Université Paris-Saclay, CEA List). Proceedings of the ACM on Programming Languages 7, POPL, Article 65, January 2023.  **Source:** https://bernsteinbear.com/assets/img/lemerre-ssa.pdf

*What I read and how: all 30 pages from the extracted text (Sections 1-9, including every definition, theorem statement and proof sketch, the Figure 9 algorithm, both use cases and the related-work section). The prose is clean. The formula boxes (Figures 3-7) and the picture of the running example (Figures 1, 2, 8) are scrambled in extraction; I reconstructed them from the surrounding explanation and the worked Examples 4.1, 5.5 and 5.7, and did not need to render pages. The paper puts its full proofs in a separate appendix (cited as Lemerre 2023a), which is not part of this PDF; what is summarised here are the in-paper proof sketches.*

## In one paragraph

Normally "convert to SSA" is a rewriting step done first, and analyses (constant propagation, value numbering, type or range inference) run afterwards on the result. But good SSA sometimes *needs* analysis results (which branches are dead? which memory cells are really distinct?), and analyses want SSA: a chicken-and-egg problem. Lemerre shows that SSA conversion can itself be phrased as an ordinary static analysis in the framework called abstract interpretation. Once it is "just another analysis", it can be run *together* with the others in one pass, each sharpening the rest. He proves the result is exactly equivalent to the original program, shows a 970-line OCaml pass that does SSA conversion, value numbering, constant propagation and loop-invariant code motion all at once, and uses the idea inside Codex, a static analyser for C and machine code.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Abstract interpretation in one sentence.** Run the program on *descriptions* of values instead of values (e.g. "some integer between 0 and 10"), merge the descriptions where control flow joins, and repeat round loops until nothing changes (a "fixed point").

**Step 1: describe each variable by a formula.** The description used here maps every program variable, at every program point, to a *symbolic expression*: a formula over named unknowns. After `inc = 1; hours = time / (inc * 3600)` the description says `hours -> time_0 / (1 * 3600)`. Two variables with the same formula are equal; that *is* global value numbering (GVN, detecting computations that always give the same result).

**Step 2: what to do at a join.** If the two incoming formulas for `x` are the same, keep it. If they differ, invent a fresh unknown named after the variable and the location, `x@L` (the paper writes x with a location subscript). That fresh unknown is exactly a Phi. Because the name is derived from (variable, location), going round a loop produces the *same* name again, so the iteration terminates.

**Step 3: remember how the unknowns are fed.** The *SSA graph* has the original program locations as nodes; each edge carries a guard (the branch condition) and a set of bindings "on this edge, `x@L` := formula". Those bindings are the Phi inputs, attached to edges rather than to a Phi instruction.

Worked example (mine, simplified from the paper's running example):

```
L0:  i = 0
L1:  while (i < 24) { i = i + 1 }
L2:  ...
```

- Analysis reaches L1 from L0 with `i -> 0`, and from the loop body with `i -> i@L1 + 1`. They differ, so `i -> i@L1` at L1.
- SSA graph edges: L0->L1 binds `i@L1 := 0`; L1->L1 (guard `i@L1 < 24`) binds `i@L1 := i@L1 + 1`; L1->L2 has guard `not (i@L1 < 24)`.
- Read conventionally: `i1 = phi(0, i1 + 1)`.

**Expressions float.** A symbolic expression is not attached to a location. Converting to ordinary SSA means naming each sub-expression, choosing where to compute it, and ordering the computations. Each expression has a *scope* (the locations dominated by the place its unknowns are introduced), which gives a legal earliest placement; so loop-invariant code motion falls out for free. The paper calls Click's sea of nodes "the closest to our SSA graphs", describing it as their lower-level form.

**Equivalence, both ways.** The SSA graph and the original program are related by a *surjective strong homomorphism* (stronger than bisimulation): every run of one corresponds step-for-step to a run of the other. So the analysis is *sound* (misses no behaviour) and *complete* (adds none).

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** the program as basic blocks ("locations") joined by edges that carry guards; a standard dataflow engine. No dominator tree, no dominance frontiers. The formal language is tiny: integer variables, constants, four arithmetic operators, assignment, sequencing; at most two predecessors per location.

**Part 1: the symbolic expression analysis (Section 4).**

1. At the entry, bind each variable `x` to the unknown `x@L0`.
2. Interpret each block: `x := e` rebinds `x` to `e` with current formulas substituted in. These steps lose nothing (they are *exact*).
3. At a join, variable by variable: same formula on both sides, keep it; different, use the unknown `x@L`. This is the only step that loses information.
4. Iterate. The space of descriptions has finite height (locations times variables), so this stops.

*Sharper version (Section 4.2).* Name the unknown after the *set* of variables that have the same pair of incoming formulas. If `time` and `i` are both `0` on one side and both `t + 1` on the other, they get one shared unknown `time_i@L1`, so the analysis knows `time == i` round the loop. An implementation just uses a fresh integer per distinct pair of formulas; that integer is the "value number".

*Why reusing names is safe.* Reusing `x@L` could in principle fake a relationship: joining `[x -> 1 + y@L6, y -> 2]` with `[x -> 1 + y@L6, y -> 3]` at L6 would claim `x = 1 + y`, which is false on both sides. The paper shows the join is sound whenever `L` does not already occur in at least one argument, and that the fixed-point computation only ever applies it in that situation.

**Part 2: from descriptions to an SSA graph (Section 5).**

- *Strictness (Theorem 5.1).* At the fixed point, any unknown `v@D` appearing in the description at location `L` has `D` dominating `L`. This is the usual SSA rule "definitions dominate uses", obtained as a theorem rather than imposed. (It can be violated mid-computation.)
- *Scope.* The scope of an expression is the set of locations dominated by the locations of all its unknowns; because dominance is a tree, a non-empty scope is "everything below one location", and that location is the most-hoisted place the expression may be computed. Example 5.5: `1 * 3600` has scope "everywhere"; `hours@L1 + hours@L3` has scope `{L3}`; `time_i@L2 + hours@L3` has empty scope and is meaningless.
- *Edges.* For each program edge `L -> L'` that is not provably dead: run `L`'s block on its description, translate the guard, and for every variable whose resulting formula differs from what `L'` expects, record a binding "unknown at `L'` := that formula". Dead edges (false guard or unreachable source) are simply left out, which is how other analyses prune Phi inputs.
- *Semantics.* A state is a location plus values for the unknowns in scope. Taking an edge requires its guard to hold, applies its bindings simultaneously, and *unbinds* unknowns that go out of scope (unusual for SSA; the author says assignment semantics also works, but unbinding matters when combining with other analyses).

**Part 3: equivalence (Theorem 5.8).** The descriptions give a map from SSA states to original states: evaluate each variable's formula. The proof sketch: because steps 2 are exact and the edge bindings put back exactly what the join threw away, this map carries every SSA step to an original step and vice versa (a *strong homomorphism*). Restricted to reachable states it is onto, which makes it a bisimulation, so the SSA graph has the same step-by-step behaviour as the source: sound and complete. Since step-by-step behaviour is the finest semantics, equivalence of traces, input/output and reachable states follows.

**Part 4: staying correct while unfinished (Section 6).** Mid-iteration the SSA graph can be *wrong*, not merely incomplete: in the paper's three-location loop, after four steps the back edge is labelled `x@L1 := 0 + 1 + 2` instead of `x@L1 := x@L1 + 1 + 2`, giving a run the real program does not have. The fix is to keep only *fully propagated* edges, those whose source description, pushed through the block, is already included in the target description (Theorem 6.2: such a partial graph never has spurious behaviour). The practical algorithm (Figure 9) follows Bourdoncle's recursive iteration over a weak topological order (inner loops stabilised first); it snapshots the SSA graph before each loop and withholds the loop's back edges until that loop has stabilised.

**Part 5: emitting ordinary SSA.** Flatten formulas into named temporaries, place each at its scope location (this is where loop-invariant code motion comes from), and order them. For compilation, guards become branch instructions.

**Implementation requirements and complexity (Section 4.3).** Hash-consing (identical formulas share one object, so equality is pointer comparison). Stores as Patricia tries ("Okasaki maps") so a join touches only the variables that differ; the author calls this the crucial engineering decision, since otherwise joins dominate the run time. Worst case O(|L|·|X|²) for |L| locations and |X| variables; typical O(|L|·log|X|). Formula evaluation may also rewrite (constant folding, arithmetic identities, normalising commutative operators) to find more equalities.

**Use case 1: one-pass optimising translation (Section 7.1).** A Frama-C plugin emitting LLVM IR: SSA translation, global value numbering, global code motion and sparse conditional constant propagation in 970 lines of OCaml (plus 316 for the tries and 183 for the iteration strategy). Tested on 100 large Csmith-generated C files restricted to non-addressable integer variables with unstructured control flow: all programs free of undefined behaviour gave the same result as a standard compiler. No loop nest needed more than 6 iterations. Estimated cost if dropped into clang: median 4.30x, worst 6.57x slower; with constant propagation and dead-code elimination combined in, median 3.19x, worst 4.73x (combining analyses made it *faster*). Whether a single-pass design can beat a pass pipeline is left as "an open question".

**Use case 2: Codex (Section 7.2).** A static analyser for C and for machine code that combines these two domains with control-flow, numeric and memory abstractions. They serve to prove equalities, to run a sparse numeric analysis simultaneously with SSA translation, and to generate simplified SMT queries at any time during the analysis (which is why Part 4 matters).

## Memory, arrays, aliasing (what it says, or "not addressed")

Explicitly deferred. The experiment avoids "the problem of addressable variables in C that cannot be directly translated to SSA". The motivation section says that precise SSA for low-level code "demands that memory locations are promoted to SSA variables", which needs memory and control-flow analyses, which need numeric analysis, which benefits from SSA; the SSA abstract domain is offered as the way to break that circle, and Codex does this. But the conclusion states the paper "did not mention how the SSA abstraction can be combined with memory abstractions to do register promotion; these studies should be the target of future publications."

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **A theory for what T1 could become.** Chalk already has abstract domains (types, integer intervals) running over a sea-of-nodes graph. This paper says SSA construction, value numbering and those domains can be one combined fixed point, with dead branches found by intervals removing Phi inputs, which sharpens the intervals. That is an argument for running T1's type and interval analyses *together*, Click-thesis style, rather than in sequence. (Inference.)
- **A correctness yardstick for B::SoN.** "The SSA graph is step-for-step equivalent to the source, and the map back is `variable -> formula at each location`" is a testable property: B::SoN could keep, per perl op, the map from pad variable to node, and a checker could replay it. A variable whose map entry is wrong (e.g. typed from a later use) breaks the homomorphism at a specific location. (Inference.)
- **Does not help with the open memory questions.** Store/Load vs effectful nodes, one chain vs slices, I/O and `die` ordering: all outside the paper's scope. The language modelled has only integer variables and assignments.

## Limits and later work

Related work the paper positions itself against: Reif and Lewis (1986) characterised the global value graph as a fixed point but rejected plain dataflow as too slow; Cooper and Simpson's optimistic value numbering is the closest existing algorithm; Braun et al. also need no prior analysis and optimise on the fly, but only with local rewrites, whereas this approach can use any semantic fact from a combined domain; Click and Paleczny's sea of nodes is "the closest to our SSA graphs"; Demange et al. (2018) give a sea-of-nodes semantics similar to the one here. Tiny core language; no memory, calls or exceptions. Performance is "compatible with inclusion in a compiler" but several times slower than clang. Combining with numeric domains is only sketched. The follow-on PLDI 2026 paper by Leissa and Griebler says they are extending this construction to higher-order programs in MimIR.
