# SSA without Dominance for Higher-Order Programs

**Authors, venue, year.** Roland Leissa and Johannes Max Griebler (University of Göttingen). Proceedings of the ACM on Programming Languages 10, PLDI, Article 208, June 2026.  **Source:** https://bernsteinbear.com/assets/img/ssa-without-dominance.pdf

*What I read and how: all 24 pages from the extracted text (Sections 1-8 including the typing and evaluation rules, every lemma and theorem with its proof line, Tables 1-2, the data-structure section and the evaluation). Prose and pseudocode are clean. Inference-rule layouts and Figures 3, 4, 7, 9 are partly scrambled but legible enough to follow with the prose; Figure 11 is nine log-log plots, of which I could use only the axis labels, legend and the discussion in Section 6.2, so the performance figures below are the ones stated in the text.*

## In one paragraph

SSA compilers lean on one rule: every use of a value must be *dominated* by its definition (every path from the start to the use passes through the definition). Dominance is computed from the control-flow graph. The authors argue this is the wrong foundation for two reasons. It is imprecise, because "comes later in control flow" is a much weaker fact than "actually depends on". And it is undefined for *higher-order* programs, where functions are passed around as values and there is no fixed control-flow graph to compute dominance on. They propose replacing dominance with a question about **free variables**: "does this piece of code mention, directly or indirectly, a variable that that piece of code introduces?" From that they build a graph-based lambda calculus (lambda-G), a *nesting tree* that plays the role of the dominator tree, and an efficient way to keep free-variable sets up to date while the program is being rewritten. It is implemented in the MimIR compiler framework, and the theorems are checked in the Lean proof assistant.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Blocks are functions; Phis are parameters.** A basic block that ends by jumping is like a function that never returns (a *continuation*). A Phi at the top of a block is that function's parameter, and each predecessor's jump supplies the argument. This is the long-known correspondence between SSA and continuation-passing style.

**Free variable.** A variable used inside a function but introduced by some other function. In Perl terms: what a closure captures.

**Nesting.** Function `A` *nests* function `B` if `A`'s parameter is free in `B`, directly or through a chain. Nothing is said about control flow. The paper proves that nesting implies dominance but not the reverse: nesting is the tighter relation.

Worked example (the paper's, Section 2):

```
hi:  i1 = phi(0, j2)          # outer loop header, parameter i1
     if i1 < n goto bi else goto xi
bi:  goto hj                  # passes i1 as the inner loop's starting value
hj:  j1 = phi(i1, j2)         # inner loop header, parameter j1
     j2 = j1 + 1
     if j1 < n goto bj else goto xj
bj:  goto hj
xj:  goto hi                  # passes j2 back to the outer loop
xi:  return i1
```

Only `bi` mentions `i1` (it hands it over as an argument). The inner loop's own blocks `hj`, `bj`, `xj` never mention it.

- *Dominator tree:* `hi` dominates `hj` and everything in the inner loop, simply because you must pass through the outer header to get there.
- *Nesting tree:* `hj`, `bj` and `xj` do not have `i1` as a free variable, so the inner loop is *not* nested in `hi`; it sits beside it. Only `bi` and `xi` hang under `hi`.

Consequence: to peel or unroll the outer loop you must copy every block that depends on `i1`. Dominance says "copy everything below `hi`", including the whole inner loop. Nesting says "copy only `hi`, its body and its exit". If you edit `xj` to compute `i2 = i1 + j1` (the paper's Figure 3c), the dominator tree does not change but the nesting tree does: the inner loop now hangs under `hi`.

**A soup of functions.** In lambda-G a program is a flat map from labels to functions; functions are not written inside one another. Scope is not syntax, it is *recovered* from free variables when needed. Bodies may be left "unset" and filled in later, which is how cycles (loops, recursion) are built.

## Construction / algorithm (steps, complexity, inputs it needs)

This is not an SSA construction paper; it assumes the program is already in SSA or lambda-G. What it provides:

**The dictionary (Table 2).** Function and basic block both become a *function*; function parameter and Phi both become its *variable*; call and jump become *application*; call argument and Phi argument become the application's argument; inlining, loop peeling and loop unrolling are all *beta-reduction* (substitute an argument for a parameter); the dominance property becomes *well-formedness*; dominance becomes *free variables*; the dominator tree becomes the *nesting tree*; loops and recursion become cycles among siblings in that tree; critical-edge elimination becomes *eta-expansion*.

**1. Free-variable analysis, lazy and incremental (Section 3.1).**
- Each expression stores, at creation, its *local variables* and *local functions* (those it mentions without looking inside other functions). Expressions are immutable; only a function's body can be swapped.
- A function's free variables are those of its body, plus those of the functions the body mentions, minus its own. Loops make this circular, so it is solved by fixed-point iteration, on demand, and cached.
- Each function has an integer *mark*; a global counter `run` goes up by 2 per query. Mark 0 means "stale, recompute"; `run - 1` means "from the previous round, refine"; `run` means "I am already on the stack: a cycle, return what we have so far"; anything else means "valid, use the cache". If no cycle was met, one pass suffices.
- At most d + 2 passes, where d is the *loop-connectedness* (most back edges on any cycle-free path).
- Each function keeps the set of functions that mention it. Changing a body resets the marks of its transitive users, and nothing else. No general def-use chains are kept.
- Table 1 traces this on the nested-loop example: 3 rounds to settle the first version; after changing one block, the unaffected exit block keeps its cached answer.

**2. Well-formedness (Section 3.2).** Nesting must not be circular. Proof idea of *nesting implies dominance* (Theorem 1): a free variable keeps propagating to callers until it meets the function that introduces it (Lemmas 1-2). So if `A`'s variable is free in `B` and some path from the root reached `B` without passing `A`, the variable would be free in the root, making `A` nest the root while the root nests `A`: a forbidden cycle. The converse fails (a block can dominate another without the other using anything of it).

**3. Dependency-aware substitution and beta-reduction (Sections 3.3-3.4).** To replace a variable by a value: any expression whose free-variable set does not contain that variable is returned untouched (one set-intersection test); otherwise recurse. A function that does depend on it is cloned: a fresh label with an *unset* body is registered first (so recursive references find it), then the body is rewritten. The calculus is shown type-safe in the usual two parts: a well-typed closed expression is a value or can step (*progress*), and stepping keeps the program well-typed and well-formed (*preservation*).

**4. Eta-expansion as critical-edge elimination (Section 3.5).** A function is *well-known* if every mention of it is as the thing being called. Passing it as a value (for instance as a branch target that also needs an argument) makes it not well-known and blocks changing its signature. Wrapping it in a trivial forwarding function for those uses restores well-knownness; for first-order programs this is exactly splitting a critical edge. The same trick lets the compiler drop a dead parameter.

**5. Nesting tree (Section 4, Figure 8).** Breadth-first from a root; attach each newly found function under the *deepest* already-placed ancestor whose variable is free in it. Then:
- *Sibling dependencies*: `A` depends on sibling `B` if something nested in `A` mentions `B`. They fix the order of siblings.
- *Loops and recursion*: run Tarjan's strongly-connected-components algorithm on sibling dependencies at each level. A self-loop is direct recursion; a larger cycle is mutual recursion. Irreducible loops show up simply as bigger cycles, with no special case. With a virtual root over all closed functions, the top level is the ordinary call graph.
- *Case study*: printing a lambda-G program as OCaml with correct lexical scopes and `let rec ... and ...` groups.

**6. Code motion (Section 4.2).** Click-style early/late placement works with the nesting tree substituted for the dominator tree: early = the expression's level in the nesting tree; late = least common ancestor of its users.

**7. Set representation (Section 5).** Every expression and function points at shared, immutable sets, so copying and equality are pointer operations. Four cases: empty (null), singleton (direct pointer), up to 16 elements (hash-consed sorted arrays), larger (an *indexed trie*: a shared prefix tree whose paths are indexed by splay trees in the manner of a link-cut tree, giving amortised logarithmic membership and a fast "do these two sets intersect?" test). Space is argued to be linear in program size for the trie against quadratic for arrays.

**Evaluation (Section 6).** Implemented in C++ in MimIR. Three *synthetic* stress programs: n consecutive loops; the same with all counters kept alive to the end; n loops nested inside each other. Three operations timed: free variables for all functions, one beta-reduction of the enclosing function, nesting-tree construction. Three set implementations compared (indexed trie, the `immer` persistent-set library, `std::set`), plus LLVM's dominator analysis and inliner as reference points (the authors stress this is "not apples-to-apples").
- The indexed trie is usually about 2x, sometimes 4x, faster than `immer`; `immer` and `std::set` ran out of memory beyond 2^13 loops on some benchmarks.
- Consecutive-loop programs scale as n log n. Free variables for over three million functions (2^20 loops) take under 4 seconds.
- Nested loops are the bad case: observed growth consistent with n^3 log^3 n for free variables and n^2 log^2 n for the other two; 2^11 nested loops took about 3 minutes. The authors' defence is that the deepest loop nest in all of SPEC2006 is 22.
- LLVM's dominance analysis is "several times faster" than the free-variable analysis. Beta-reduction is generally faster than LLVM inlining except on large loop nests.
- One realistic program, a regular-expression matcher of 1,058 blocks: free variables 476 microseconds against about 100 for LLVM dominance; beta-reduction 9,755 against about 3,800 for inlining alone (about 9,400 with clean-up passes).

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed. The calculus has integers, booleans, tuples and functions; there is no store. The only links are that the implementation "operates on a Sea of Nodes" (expressions are nodes constrained only by their dependencies, so `let` bindings in the examples are just for readability) and a related-work paragraph on sea-of-nodes IRs. (In MimIR and its predecessor Thorin, memory is threaded as an explicit value much as in Click and libFIRM; that is my background knowledge, not in this paper.)

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Mostly a "know it exists" paper for chalk today.** Chalk's central open questions are about memory, which this paper does not touch.
- **Closures are where it becomes relevant.** Perl is a higher-order language: anonymous subs capture lexicals. Chalk currently sidesteps the issue by putting closure-captured scalars in memory, so each sub is a first-order graph and dominance works inside it. That is sound. This paper describes the alternative road: represent subs and their captures directly, and let free-variable sets say what depends on what. If chalk later wants to inline closures or specialise a `map`/`grep`/`sort` block, "which nodes depend on this sub's parameters?" is precisely a nesting question. (Inference.)
- **Free variables = captures = a declaration-level fact.** Which lexicals a sub captures is decided by perl at compile time and recorded in the pad (outer/"fake" entries). B::SoN should classify a scalar as "captured, therefore in memory" from that declaration-time information, not from how a use site looks. The paper's well-formedness rule is a useful mental check on that classification. (Inference.)
- **Sharper scheduling.** If chalk implements Global Code Motion, note that dominance-based "earliest block" can be needlessly deep; a node that does not depend on a loop's Phis need not be considered inside the loop at all. In a sea of nodes this precision is already available from the data edges, which is the paper's point made from the other side.
- **Does not apply:** the lambda-G calculus itself, the trie data structures, Lean proofs. Chalk lowers to LLVM IR, which is first-order and dominance-based.

## Limits and later work

The related-work section adds two points worth keeping: in this setting classical *liveness* "corresponds exactly to free-variable information"; and sibling dependencies resemble the join edges of Sreedhar and Gao's DJ-graph, but record data-flow rather than control-flow joins. Dependent types and other binders are said to be supported in MimIR by the same machinery (Section 3.6). No SSA construction (the authors say they are working on one for MimIR that extends Lemerre's abstract-interpretation approach to higher-order code). No treatment of side effects. Evaluation is scaling behaviour on MimIR workloads rather than end-to-end compiler speed or code quality. The authors grant that dominance "remains valuable in some contexts", for example classical SSA construction before SSA variables exist.
