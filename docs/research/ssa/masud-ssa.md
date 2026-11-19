# More Precise Construction of Static Single Assignment Programs Using Reaching Definitions

**Authors, venue, year.** Abu Naser Masud and Federico Ciccozzi (Mälardalen University, Sweden). Preprint submitted to Elsevier, 31 March 2020; an invited extension of their IEEE SCAM conference paper "Towards constructing the SSA form using reaching definitions over dominance frontiers". (I believe the journal is the Journal of Systems and Software; the extracted text does not say.)  **Source:** https://bernsteinbear.com/assets/img/masud-ssa.pdf

*What I read and how: all 33 pages from the extracted text (mostly clean; set-notation subscripts are a little scrambled): Sections 1-8 including Algorithms 1-5, the worked Examples 1-3, the lemmas and both theorems with their proofs, and Tables 1-5. Figures 6-8 are bar/line charts; I used the tables they plot.*

## In one paragraph

The standard recipe for deciding where Phi nodes go (Cytron et al., "dominance frontiers") quietly assumes that **every variable is defined at the very start of the function**. For parameters and globals that is true. For local variables declared and first assigned somewhere in the middle it is false, and the false assumption makes the recipe insert Phis that merge a real value with a non-existent "value at entry". This paper measures how many: in seven SPEC CPU2017 C programs compiled through Clang/LLVM, on average 69% more Phis than necessary (up to 87%). It then gives a different placement algorithm based on *reaching definitions* (which assignments can arrive at this point?) that places exactly the needed Phis, at a higher but usually tolerable cost.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**When is a Phi needed?** At a join point where two *different* assignments to the same variable can both arrive. Formally the set of such join points for a set `S` of assigning blocks is called the *join set* `J(S)`.

**Why the standard method over-approximates.** Dominance frontiers compute the join set correctly *only if* the entry block is counted among the assigning blocks. Adding entry to `S` is harmless for a parameter but invents a phantom definition for a late-declared local.

Worked example (mine, in the spirit of the paper's Figure 3a, which comes from `perlbench`):

```perl
for (...) {
    my $ix = 0;            # only definition of $ix
    while (cond) { $ix++ } # second definition, inside
    ...
}
```

With "entry defines `$ix`" assumed, the outer loop header sees two definitions arriving (the phantom one from before the loop, and the one from the previous iteration), so it gets `ix = phi(undefined, ix_prev)`. Nothing ever reads that Phi; it is dead. Removing dead Phis afterwards needs a liveness analysis.

**Worse: some superfluous Phis are live.** Figure 3b: a variable declared at the top, assigned on one path, then returned. The phantom entry definition meets the real one at intermediate joins, creating Phis that *are* on the path to the `return`, so liveness-based pruning keeps them. Only dropping the false assumption removes them.

**Reaching definitions with placeholders.** A *concrete definition* (CD) is a block that really assigns `x`. An *abstract definition* (AD), written `n_u`, is a placeholder meaning "whatever definition of `x` reaches block `n`". The analysis first sweeps the graph once, recording at each block either the CD that reaches it or an AD. It then *resolves* ADs to CDs. A join needs a Phi for `x` exactly when more than one concrete definition reaches it.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** a complete control-flow graph and, for each block, the set of variables it assigns. No dominator tree. Only parameters and globals are treated as defined at entry.

1. **Forward dataflow (Algorithm 1).** Visit each edge once (no iteration to a fixed point). For each block and variable compute the reaching set on entry and exit; where the predecessor has nothing concrete to offer, pass along an abstract definition.
2. **Resolve abstract definitions (Algorithms 2-4).** For each variable, build a small graph over the ADs, and repeatedly substitute concrete definitions for placeholders until nothing changes.
3. **Place Phis** at joins where the resolved set has two or more concrete definitions.
4. Renaming (giving each definition its SSA name) is the usual second phase and is "skipped in this paper".

**The algorithm in more detail.**

- *Sweep (Algorithm 1).* A worklist of edges, each visited once. The transfer rule per block and variable: if the block assigns `x`, or more than one concrete definition arrives, the block itself becomes the definition leaving it; if placeholders arrive and at most one concrete definition, the outcome is undecided, so the block emits its own placeholder; otherwise pass the incoming set through. Lemma 1: at most one definition leaves a block, so at most (number of predecessors) arrive at the next.
- *Dependency graph.* For a join whose answer is undecided, collect the equations "what arrives at join n" for every join it transitively refers to. These equations may be circular (loops). Draw them as a small graph whose nodes are concrete definitions and placeholders.
- *Flow of concrete definitions (Algorithm 2).* Push each concrete definition forward through that graph, stopping at nodes already known to be definitions, and record for each placeholder the set of concrete definitions that reach it.
- *Which placeholders are really Phis (Algorithm 3, Definition 5).* Receiving two or more concrete definitions is necessary but **not sufficient**: an upstream placeholder may itself turn out to be a Phi, in which case it, not the things behind it, is what reaches downstream. So only the *first* placeholder along each path that receives several definitions is declared a Phi.
- *Iterate (Algorithm 4).* Newly found Phis become concrete definitions; repeat flow and detection until no new Phi appears; then rebuild each node's reaching set (Algorithm 5).

**The paper's running example (Figure 4, Examples 1-3)** is `Perl_ninstr` from perlbench: an outer `while`, an inner `for`, and a `goto OUTER`, i.e. unstructured control flow. For variable `x` the sweep leaves four joins undecided. Flow analysis says three concrete definitions reach both the outer-loop join and the next join down. Detection declares the inner-loop join and the outer-loop join to be Phis, but *not* the next join down, even though it too "receives" three definitions: in the next round the only thing that reaches it is the outer-loop Phi, so it needs none.

**Correctness (Section 5.1), main ideas.** Lemma 4: a placeholder that receives at most one concrete definition will never receive more in later rounds and never becomes a Phi. Lemma 5: in each round, the placeholders *not* selected by Definition 5 cannot be Phis on account of the current definitions. Lemma 6: when a round selects nothing, every placeholder is either settled or receives at most one definition. Theorem 1: the sets found in successive rounds are disjoint and the graph is finite, so the process stops, and by Lemmas 5-6 it has found all Phis and only Phis.

**Complexity (Section 5.2).** With N blocks, V variables, K the largest number of predecessors of any join, and N_mu the size of a dependency graph (at most N): the sweep is O(N·V·K); one flow pass O(|C|·K·N_mu) for |C| current definitions; one detection pass O(K·N_mu); the whole algorithm O(K·N³·V + K·N²·V²) (Theorem 2). That is much worse on paper than dominance-frontier methods; the authors' defence is that dependency graphs are "usually very small" when assignments are sparse, and they concede it "may take longer time if the code contains dense variable definitions".

**Evaluation (Section 6).** Both methods implemented in Clang/LLVM; seven C benchmarks from SPEC CPU2017 (about 2,081 thousand lines); each procedure analysed separately; some files skipped because Clang could not parse them.

*Table 3, Phi counts (RD = this paper, DF = Cytron).*

| Benchmark | Phis RD | Phis DF | superfluous | superfluous ignoring Phis at the exit block |
|---|---|---|---|---|
| 544.nab | 26,960 | 44,600 | 65.43% | 51.47% |
| 557.xz | 820 | 1,300 | 58.53% | 46.27% |
| 500.perlbench | 124,210 | 220,340 | 77.39% | 65.50% |
| 502.gcc | 430,910 | 807,190 | 87.32% | 68.56% |
| 505.mcf | 3,090 | 4,730 | 53.07% | 41.55% |
| 525.x264 | 23,750 | 40,030 | 68.55% | 57.15% |
| 538.imagick | 38,320 | 67,750 | 76.80% | 31.06% |
| average | | | 69.59% | 51.65% |

"Superfluous" is (DF / RD - 1) x 100. The last column discounts Phis placed at the function's exit block, where locals are dead anyway. If every variable is declared as defined at entry, the two methods give exactly the same count.

*Table 4, time relative to Cytron, by share of procedures.* Within 2x: 65.63% on average (35.75% for mcf up to 92.96% for xz). Between 2x and 5x: 25.09%. More than 5x: 9.28% (up to 19.15%, for perlbench).

*Table 5, 28 source files of perlbench.* Superfluous Phis from 15% (`perly.c`) to 169% (`dump.c`), average 74%. Times are mostly comparable, but a few files blow up: `toke.c` 33.3 s against 0.48 s, `regcomp.c` 27.1 s against 2.8 s, `regexec.c` 13.4 s against 0.49 s, `pp_pack.c` 8.3 s against 0.19 s. The extra time is in the iterative resolution, not the single sweep. (These are the perl interpreter's lexer and regex engine: large functions with dense assignments and `goto`s.)

**Related work (Section 7).** Surveys placement algorithms since Shapiro and Saint; notes that linear-time dominance-frontier variants (Sreedhar and Gao's DJ-graphs) were not faster in practice per Bilardi and Pingali; pruned (Choi et al.) and semi-pruned (Briggs et al.) SSA still rest on the entry assumption; and that syntax-tree methods (Brandis and Mössenböck; Click and Paleczny; Aycock and Horspool; Braun et al.) exist, with Braun et al. reporting instruction counts similar to Cytron's in LLVM.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed, by explicit statement: "Our SSA construction approach which only deals with scalar variables is orthogonal to the practical methods modeling aliasing, non-scalar variables such as structures or arrays, and indirect memory operations in the SSA form."

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **The warning is about scope, and Perl is scope-heavy.** `my` variables are routinely declared inside loop bodies and branches. Any construction that treats every pad entry as "defined at sub entry" will create Phis at enclosing loop headers that merge the variable with a value from before it existed. Those Phis are noise for T1's type and interval analysis: a Phi of "int in [0,10]" with "undefined/any" widens to something useless. (Inference.)
- **This connects to "typing by declaration".** The fix the paper motivates is to make the *declaration point* the start of a variable's life. In B::SoN terms: the op that introduces the pad variable (`padsv` with the intro flag, i.e. `my $x`) is a definition (of `undef`, in Perl), and the variable does not exist before it. (Inference.)
- **Chalk probably does not need this algorithm.** A demand-driven construction (Braun et al., libFIRM) only creates a Phi when a *read* asks for one, so the dead phantom Phis never appear. The *live* superfluous kind can still arise if a read can reach back past the declaration; in Perl each `my` re-executes and resets the variable to `undef`, which acts as a fresh definition and cuts that path. So: treat `my` as a definition and the problem largely disappears without the cubic algorithm. (Inference; the paper compares only against Cytron in LLVM and notes that Braun et al. report Phi counts similar to Cytron's there.)
- **Use it as a reference oracle.** The authors themselves suggest their method "can be seen as a reference method computing an optimal number of Phi-functions". A test could count B::SoN's Phis against a reaching-definitions count on small subs.
- **Memory chain.** The memory value really is defined at entry (`MemStart`), so the entry assumption is *correct* for memory and nothing here changes memory Phi placement. (Inference.)

## Limits and later work

Scalars only. The headline 69% compares against Cytron *without* pruning; even after discounting exit-block Phis it is 52%, but there is no comparison against pruned SSA or against a demand-driven construction. Worst-case cost is polynomially worse than established methods, and the authors list improving it as future work. Evaluation is on C via Clang only, against one baseline. Renaming is not covered. The comparison baseline is un-pruned Cytron; how much of the 69% would be removed by pruned or semi-pruned SSA is discussed only through examples.
