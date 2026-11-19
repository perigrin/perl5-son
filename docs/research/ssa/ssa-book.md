# SSA-based Compiler Design (the SSA book)

**Editors, publisher, year.** Fabrice Rastello and Florent Bouchez Tichadou (editors), with about thirty contributing authors. Springer, 2022, as *SSA-based Compiler Design*. **Source:** https://link.springer.com/book/10.1007/978-3-030-80515-9 (published edition); https://bernsteinbear.com/assets/img/ssa-book.pdf (the PDF copy summarised here).

*Important note on the copy. The PDF is not the 2022 Springer text. It is a build of the manuscript dated "Wednesday 30th May, 2018", 332 pages, 19 chapters, with a placeholder cover, an empty foreword and "TODO" notes. The published book has 24 chapters. The draft itself says "HSSA form (not described in this book)" (p. 146) and has dangling references to "Chapter hssa" and "Chapter sccp". So four chapters we would want are absent from our copy: the Part II introduction and "Propagating Information Using SSA" (sparse data-flow propagation and conditional constant propagation), "Hashed SSA Form: HSSA", "Instruction Code Selection", and "Register Allocation". That list of missing chapters is from my memory of the published table of contents; check it against the Springer page. Everything below is from the draft text unless marked otherwise.*

*Extraction note. `pdftotext -layout` interleaves the margin index terms with the prose (a heading reads "CHAPTER 9 elimination|mainidx"), flattens every figure into loose tokens (the graphs in Figs. 12.1, 12.5 and 12.7 are unreadable), and loses mathematical symbols ("k 6= i" is "k ≠ i", a lone "u" is the lattice meet, "A0" is a struck-through zero meaning "not null"). The comparison operator in equation 14.1 is lost; from context it is "at least as recent as". Fig. 14.2 has "C := i < n" where Fig. 14.1 has "i < 2"; that inconsistency is in the source. Prose is otherwise readable.*

*Page numbers below are the printed ones. PDF page = printed page + 14.*

## What the book is and how it is organised

SSA (static single assignment) is a naming rule: every variable is assigned in exactly one place in the program text, and where two control-flow paths meet a **phi function** (written φ) picks whichever version arrived. The book's "key message" (p. 5) is that unique names for distinct things remove uncertainty. It is a handbook written chapter by chapter by the people who did the research, so the tone and depth vary.

The draft has four parts.

**Part I, Vanilla SSA** (the basics)
1. Introduction (J. Singer), p. 5
2. Properties and Flavors (P. Brisk, F. Rastello), p. 15
3. Standard Construction and Destruction Algorithms (J. Singer, F. Rastello), p. 27
4. Advanced Construction Algorithms for SSA (D. Das, U. Ramakrishna, V. Sreedhar), p. 45
5. SSA Reconstruction (S. Hack), p. 59
6. Functional Representations of SSA (L. Beringer), p. 67

**Part II, Analysis**
7. Liveness (B. Boissinot, F. Rastello), p. 95
8. Loop Tree and Induction Variables (S. Pop, A. Cohen), p. 111
9. Redundancy Elimination (F. Chow), p. 121

**Part III, Extensions**
10. Introduction (V. Sarkar, F. Rastello), p. 143
11. Static Single Information Form (F. Pereira, F. Rastello), p. 149
12. Graphs and Gating Functions (J. Stanier), p. 169
13. Psi-SSA Form (F. de Ferrière), p. 185
14. Array SSA Form (V. Sarkar, K. Knobe, S. Fink), p. 199

**Part IV, Machine Code Generation and Optimization**
15. SSA Form and Code Generation (B. Dupont de Dinechin), p. 219
16. If-Conversion (C. Bruel), p. 233
17. SSA Destruction for Machine Code (F. Rastello), p. 249
18. Hardware Compilation using SSA (P. C. Diniz, P. Brisk), p. 267
19. Building SSA in a Compiler for PHP (P. Biggar, D. Gregg), p. 285

Two things to know before reading. First, almost the whole book assumes a **control-flow graph** (CFG: basic blocks of straight-line code joined by jump edges) with SSA names inside the blocks. The phrase "sea of nodes" never appears; Cliff Click is cited only as the origin of a construction algorithm (p. 66) and in the bibliography. The nearest relative of B::SoN in the book is the Value State Dependence Graph in Chapter 12. Second, the book's scope is one procedure at a time (p. 68).

## Chapter by chapter

### 1. Introduction (Singer)

Defines SSA and explains why it pays. In ordinary data-flow analysis the compiler keeps a table of facts about every variable at every point in the program; this is called **dense**. Under SSA a fact such as "this is the constant 3" or "this is never zero" is fixed at the single place a name is defined, so it can be stored once, on the name; this is called **sparse**. The chapter's example (non-zero analysis, pp. 10-11) needs six facts sparse where the dense version needs a table for each end of six blocks. It warns that some facts change at places that are not definitions (Chapter 11), and lists three "myths" about SSA (too many variables, hard to maintain, too many copies on the way out) that later chapters answer.

### 2. Properties and Flavors (Brisk, Rastello)

A vocabulary chapter. **Def-use chains** link a definition to its uses; under SSA the reverse link is a single pointer, which is what makes an SSA graph cheap. **Minimal** SSA has the fewest phis that still give every point one reaching definition. **Strict** SSA has the **dominance property**: every use is reached only through its definition (block A *dominates* block B if every path from the start to B passes through A). **Pruned** SSA drops phis whose result is never used. **Conventional** SSA is the state straight after construction, where all names joined by phis can be merged back into one variable without clashes; optimisation destroys that property. For chalk this is mostly a glossary: a sea-of-nodes graph is strict and pruned by construction (my observation, not the book's).

### 3. Standard Construction and Destruction (Singer, Rastello)

**Central idea.** The classic way to build SSA (Cytron and colleagues) has two phases. Phase one decides where phis go. A definition in block B "owns" everything B dominates; the first blocks just outside that region, where another path can sneak in, form B's **dominance frontier**, and those are the places a phi is needed. A phi is itself a new definition, so the calculation is repeated until nothing changes (the *iterated* dominance frontier). Phase two walks the dominator tree keeping, for each variable, "the version currently in scope", renaming each use to that version and each definition to a fresh one.

**Small example.**

```
x = 1;                 x1 = 1
if (c) { x = 2 }       if (c) { x2 = 2 }
print x                x3 = phi(x1, x2);  print x3
```

The assignment inside the `if` dominates only its own block; the join after the `if` is its frontier; so the phi goes there.

**What the result is** (p. 35): minimal, with the dominance property, conventional, and *not* pruned. **Destruction** (leaving SSA) replaces each phi by copies on the incoming edges, which needs care at **critical edges** (from a block with several exits to a block with several entries).

**For chalk.** B::SoN builds from perl's op tree, not a CFG, so this is background; but "current version in scope" is the mental model a memory chain needs too.

### 4. Advanced Construction Algorithms (Das, Ramakrishna, Sreedhar)

Three faster ways to compute where phis go, without building every dominance frontier first: two using the "DJ-graph" (the dominator tree plus the remaining join edges) and one using the **loop nesting forest** (the tree of which loops sit inside which). The authors admit the algorithms are hard to compare, and that in production compilers renaming, not phi placement, is the expensive part (p. 57). Not something chalk needs.

### 5. SSA Reconstruction (Hack)

**Central idea.** Optimisations break SSA: duplicating code, or inserting a reload, gives one name two definitions. This chapter is about repairing SSA for one variable without rebuilding everything. Two algorithms are given.

The first reuses the dominance frontier and the dominator tree, so it suits passes that leave control flow alone.

The second is the one that matters to us. It needs no dominance information at all. Starting from a use, it searches backwards through the control flow for the definition. Each block caches "the version live at my start". If a block has one predecessor, ask it. If it has several, create a phi *first*, record it as the block's answer (so a loop does not recurse forever), then ask each predecessor to fill in an operand. Afterwards any phi whose operands are all the same value, or itself, is removed. The book says this is "based on the algorithm by Braun et al. which is an extension of the construction algorithm that Click describes in his thesis to construct SSA from an abstract syntax tree" (p. 66).

**Example.** In `while (c) { $x = $x + 1 }`, asking for `$x` inside the loop body reaches the loop header, which has two predecessors, so a phi is created and cached; the back edge then asks for `$x` at the end of the body, which is the result of the `+`, whose input is the phi just created. The cycle closes instead of looping.

**For chalk.** This is the construction style a sea-of-nodes builder working from a tree uses. *My inference:* the algorithm does not care what kind of thing the "variable" is, so the memory state can be run through it as one more variable; memory phis at joins and loop headers then fall out with no special code.

### 6. Functional Representations of SSA (Beringer)

Shows that an SSA program is a functional program in disguise: a basic block is a function, a phi is that function's parameter, a jump is a call, a `let` is an assignment, and "definition dominates use" is ordinary lexical scope. The practical argument (p. 67) is that a functional form enforces SSA's rules *by construction* instead of by a checker run after each pass. The further-reading section notes that monadic intermediate languages separate pure values from "computations" and so "treat side-effects (memory access, IO, exceptions, etc.) in a uniform way" (p. 90). It gives no memory model of its own.

### 7. Liveness (Boissinot, Rastello)

A variable is **live** at a point if its value may still be needed later. Under strict SSA it can be computed in two passes, or answered by query from facts about the CFG alone. Needed for register allocation and leaving SSA, both of which LLVM does for us. Skip.

### 8. Loop Tree and Induction Variables (Pop, Cohen)

Two ideas. First, an experiment: print the SSA instructions with the CFG thrown away. In straight-line code the def-use links alone are enough to recover a valid order, and the book says so with a telling qualifier: "in the absence of side effects" (p. 112). For loops you need a little more: an extra phi at each loop exit for every value that leaves the loop, carrying the exit condition (**loop-closed SSA**). Second, **induction variables** (loop counters and their relatives) show up as cycles in the SSA graph through a loop-header phi, and can be summarised as "chains of recurrences": `{0, +, 1}` means "starts at 0, adds 1 each trip". From that the trip count and final value can be computed. Relevant to T1's interval analysis later; the first half is a tidy statement of why a floating-node graph must have an explicit ordering edge for effects.

### 9. Redundancy Elimination (Chow)

**Central idea.** A computation is **fully redundant** if it has already been done on every path reaching it, and **partially redundant** if on only some. Partial redundancy elimination (PRE) inserts the computation on the paths that lack it so the later one can be deleted; this covers both common-subexpression elimination and hoisting out of loops. The chapter's insight (pp. 122-123): after an occurrence of `a+b`, everything it dominates sees it as fully redundant, and past the dominance frontier it becomes partially redundant. Frontiers are where phis go, so the same machinery works for expressions. The SSAPRE algorithm builds, in effect, an SSA form for each expression and uses it to decide where to insert and what to delete.

**Loads and stores (section 9.4, pp. 131-135).** This is the part for us. "Register promotion" (keeping a memory value in a temporary) is PRE applied to loads and then to stores:

- A load is an expression: later loads of the same location are redundant.
- A store `X = e` is treated as `r = e; X = r`, and it starts a new version of the location. Any later load in the same version can use `r` instead (store-to-load forwarding).
- Stores are the mirror image: an *earlier* store is redundant if a later one overwrites it with no read between. To move stores later the chapter uses the mirror of SSA, **static single use** (SSU) form, with σ functions at branches.

**Example.**

```
$h{k} = 1;          # store: new version
print $h{k};        # load, same version: reuse the 1, no lookup
```

The chapter simply *assumes* the program is already in HSSA form "that completely models the aliasing in the program" (p. 122), and that for scalar variables aliasing is "completely modeled by the χ and µ functions" (p. 133). In other words: redundancy elimination on memory is easy once memory versions exist, and it is the memory versioning that carries the correctness.

**Value numbering (section 9.5).** Hash-based value numbering gives two expressions the same number when they have the same operator and operands with the same numbers; SSA makes this work across a whole procedure. It is "pessimistic": at a loop-header phi the back-edge operand is not numbered yet, so two counters that move in step get different numbers. The partition-based alternative is "optimistic" (assume equal, split until stable); it handles loops but cannot use commutativity or algebraic simplification. The chapter recommends only removing *full* redundancies among same-numbered values, since partial ones are rare and awkward.

### 10. Part III Introduction (Sarkar, Rastello)

Five pages that are the best map in the book of *why* plain SSA is not enough: facts arise at places other than definitions (Chapter 11), control conditions need representing (12, 13), and arrays and memory need representing (14). Section 10.6, "Memory based data flow", is one page and is quoted at length in the memory section below.

### 11. Static Single Information Form (Pereira, Rastello)

**Central idea.** SSA lets you hang a fact on a name only if the fact is true *wherever the name is live*. That holds for facts created at definitions. It fails for facts created elsewhere. Two examples from the text:

- After `if ($i < 100)`, inside the true branch `$i` is at most 99. Same name, different fact, depending on where you stand.
- After `$v->m()` succeeds, `$v` is known not to be null. That is true *after* the call, not before it.

The fix is always the same: **split the live range**, meaning give the value a new name at the point where the fact changes. Then each name again has one fact. A representation that achieves this for a given analysis has the **Static Single Information (SSI) property** (four conditions, p. 153).

**The tools.** A **σ function** (sigma) is the mirror of a phi: at a branch it gives the value a different name on each outgoing edge. A **parallel copy** renames a value at an ordinary instruction (`v1.m() || v2 = v1`).

**Example (range analysis, Fig. 11.2).**

```
i2 = phi(i1, i4)
if (i2 < 100) { (_, i3) = sigma(i2);  i4 = i3 + 1 }
```

Now `i3` can carry the interval `[0, 99]` for its whole life, `i4` gets `[1, 100]`, `i2` gets `[0, 100]`. Splitting at definitions and at conditionals like this is called **e-SSA** (extended SSA).

**Which direction.** Fig. 11.5 (p. 161) is a table of where each analysis must split: constant propagation and alias analysis at definitions only (plain SSA suffices); range and taint analysis at definitions and after conditionals; null-pointer analysis at definitions and uses, propagating forward; **class or type inference at uses, propagating backward**.

**For chalk.** (1) T1's integer intervals need the split at conditionals; in a sea of nodes that is a small node pinned under the branch that renames the value (my mapping). (2) The known bug "variables typed by use instead of declaration" is the mistake this chapter describes: a fact learned at a use was attached to a name that is also live *before* that use, and on other paths.

### 12. Graphs and Gating Functions (Stanier)

**Central idea.** A tour of graph-shaped program representations, moving step by step from "CFG plus def-use links" towards "no CFG at all". This is the chapter nearest to B::SoN.

- **SSA graph**: instructions and phis as nodes, an edge from each use to its definition. "Demand-based": to compute a node, first demand its operands. It "typically needs a companion representation such as the CFG" to stay correct (p. 170).
- **Program Dependence Graph (PDG)**: adds **control dependence** edges. Statement S is control dependent on a branch if the branch decides whether S runs. "Region" nodes group statements with identical conditions.
- **Gated SSA (GSA)**: a plain phi does not say *which* input to take, so the graph cannot be executed on its own. GSA replaces phis with **gating functions** that carry the condition: `phi_if(p, v1, v2)` (if p then v1 else v2), `phi_entry(init, iter)` at loop headers, `phi_exit(p, v)` for the value leaving a loop. Later papers call these γ, μ and η. The text notes a limit: this "does not allow for an interpreter to decide whether an instruction with a side effect ... has to be executed or not" (p. 175).
- **Value State Dependence Graph (VSDG)**: the end of the road. No CFG. Nodes are pure value nodes, γ nodes (conditionals), θ nodes (loops), and **state nodes** (side effects). Two kinds of edge: **value dependency** and **state dependency**.

**The VSDG's state edge (pp. 180-182).** The definition is worth having verbatim: state dependency "represents two things; the first is essentially a sequential dependency required by the original program, e.g. a given load instruction may be required to follow a given store instruction without being re-ordered, and a return node in general must wait for an earlier loop to terminate even though there might be no value-dependency between the loop and the return node." Extra "serializing" state edges are added later to pin down one execution order for code generation. "Loads and stores compute a value and state." A call is a state node "as the function body may read or update state." Every function has one return node which returns at least one result, "which will be a state value in the case of void functions".

**Dead node elimination (Algorithm 12.1).** Mark everything reachable backwards from the exit node along value *and* state edges; delete the rest. Two linear passes.

**Example.** `$a[0] = 1; return 7;` The 7 does not depend on the store by value. The store survives only because the return node depends on the state the store produced.

**For chalk.** The VSDG is a sea of nodes with one state chain. It shows the design working and its price: one "state" stands for memory contents, I/O order *and* loop termination at once. And it makes the "writes floating off the chain" bug precise: a write not on the state path from the exit is, by definition, dead code.

### 13. Psi-SSA Form (de Ferrière)

Some processors can attach a condition to an instruction: `p ? a2 = op` runs only if `p` is true. Then `a2` is not a full definition, because if `p` is false the old value survives, and SSA's "one definition, complete" rule breaks. The fix is a **ψ function** (psi): `a3 = psi(a1, p ? a2)`, read left to right, "the last argument whose condition holds wins". Unlike a phi it is an ordinary instruction inside a block, and argument order matters. Constant propagation, dead code elimination and value numbering carry over by treating ψ like φ. Aimed at low-level code generation, so not for chalk, but the *shape* is worth noticing: "a definition that may or may not overwrite" is handled by a merge node that takes the old value as an input. Memory writes are handled the same way everywhere else in the book.

### 14. Array SSA Form (Sarkar, Knobe, Fink)

**Central idea.** Treat a whole array as one SSA value. The trouble is that `A[i] = v` does not replace the array; it changes one slot. A later read `A[k]` might see the new value (if `k == i`) or the old array (if not). Array SSA makes that explicit with a **definition-phi** (dφ) placed immediately after each element write, merging "the one element just written" with "the array as it was":

```
A1[k] = v            # names the write
A2 = dphi(A1, A0)    # A2 = A0 everywhere except slot k
... A2[j] ...        # every later read names A2
```

The text states why scalars never needed this: "a scalar definition completely kills the old value of the variable" (p. 200). Ordinary phis at control joins are kept and called control phis.

**Full versus partial.** *Full* Array SSA gives each write a shadow "@ variable" recording *when* each element was last written (an iteration timestamp), so that the phi can really be executed, element by element, at run time. This was designed for parallelisation. *Partial* Array SSA drops the timestamps and is just the naming scheme, for static analysis. Partial needs no assumptions about loop shape, and for scalars it is identical to ordinary SSA.

**Analysing it.** The worked analysis is constant propagation through elements. The fact kept for an array version is a short list of `(index, value)` pairs known to be constant; everything else is unknown. The rules:

- Write `A1[k] = v` with both constant: the list `<(k, v)>`.
- `dphi(A1, A0)`: keep from A0 only pairs whose index is **definitely different** (DD) from k, then add the new pair.
- Control phi: keep only pairs present on both sides.
- Read `A[k]`: if some pair's index is **definitely the same** (DS) as k, the answer is that pair's value.

**Example (Figs. 14.7-14.11).** `Y[3] = 99; if (C) { D[1] = Y[3]*2 } else { D[1] = Y[I]*2 }; Z = D[1]`. If `I` is unknown, `Z` is unknown. If `I` is known to be 3, both branches give `D[1] = 198` and `Z` is the constant 198.

**DS and DD for non-constant indices.** DS is "same value number" from global value numbering. DD is harder and not transitive; examples given are `i` versus `i+1`. When unsure, both are false, which is always safe.

**Extension to objects (section 14.3).** For each field `x`, imagine one **heap array** `H_x` holding that field of *every* object, indexed by object reference. `p.x` is `H_x[p]`. Distinct fields get distinct heap arrays because in a strongly typed language they cannot overlap. Now "do `p.x` and `q.x` alias?" becomes "is p DS or DD to q?". DD for references comes from allocation sites: two different `new`s differ, and a fresh `new` differs from any reference that existed before it. A third merge, the **use-phi** (uφ), links successive reads so that a second read can reuse a first. "Index propagation" computes which indices have a value available in a temporary; loads at those indices are replaced by the temporary (**scalar replacement**).

**For chalk.** This is the deferred layer almost exactly, and the dφ is the `update(a, i, v)` operation under another name. What the chapter does *not* cover: doing the update in place when the old version is dead (there is no discussion of uniqueness), hashes with string keys (the DS/DD machinery is generic, but all examples are integer subscripts and object references), or escape analysis beyond the two allocation-site rules.

### 15. SSA Form and Code Generation (Dupont de Dinechin)

An engineering survey of keeping SSA alive on machine instructions: instructions with several results, operands tied to particular registers, and definitions that do not fully overwrite. One passage generalises well (p. 223): a status register holds several independent bit-fields, some "sticky", so "any operation that partially reads or modifies the register bit-fields should appear as reading and writing the corresponding variable." That is the memory-chain rule stated for a different kind of shared state. Section 15.1.5 distinguishes **invariants** of the representation (true before and after every pass) from **transient** information (recomputed when needed), and advises making def-use links and phi/edge ordering invariants. The rest is back-end material.

### 16. If-Conversion (Bruel)

If-conversion turns a small `if/else` into straight-line code: compute both sides, then pick with a `select` (the machine-level phi with a condition). It replaces control dependence with data dependence. The constraint that matters to us (p. 235): "To be speculated, an instruction must not have any side effects, or hazards", and "Memory operations are a major impediment to if-conversion." In B::SoN terms, a pure floating node may be evaluated early; a node that can write, die, or do I/O may not, and must stay tied to its control and effect inputs.

### 17. SSA Destruction for Machine Code (Rastello)

The careful version of leaving SSA: correctness when edges cannot be split, removing copies by merging names whose values do not interfere, and doing it fast enough for a JIT. Noted for completeness; chalk hands SSA to LLVM and never destroys it itself.

### 18. Hardware Compilation using SSA (Diniz, Brisk)

When C-like code is compiled to circuits, a phi *is* a multiplexer (a switch choosing one of several inputs) and both branches of an `if` can be computed at once in separate logic. Does not apply to chalk.

### 19. Building SSA in a Compiler for PHP (Biggar, Gregg)

**Central idea.** In C or Java it is easy to say which variables can be SSA values: those whose address is never taken. In a scripting language you cannot tell by looking. The chapter is an experience report from `phc`, an ahead-of-time PHP compiler, and the nearest thing in the book to chalk's situation.

**Why it is hard.** A PHP variable can become a reference at run time with no declaration (`$y =& $x`), and whether a function parameter is a reference depends on the caller. So in `function foo($x, $y) { $x = $x + $y; return $y; }` the assignment may change `$y`. Beyond references: **variable-variables** (`$$name = 6` writes whichever variable the string names), `eval` and `include` of computed strings, and **object handlers** written in C that run on read or write and can touch any variable.

**What they did.** A whole-program analysis *before* SSA, structured as symbolic execution, computing three things together at every program point: a points-to graph (who may or must alias whom), a set of possible types per variable, and constants. Doing the three together "greatly improves the precision" (p. 295); constants prune branches, types prune method targets. From the alias results they compute, for each statement, which names it **must define**, **may define**, and **uses**. For `$x = $y`: `$x`'s value is defined; every must-alias of `$x` is defined; every may-alias is may-defined.

**Then HSSA-style SSA.** They "give names to all memory locations in our program, including locations inside arrays and hashtables, if they are directly referred to in source", and add **μ** (mu, may-use) and **χ** (chi, may-define) operations. A variable-variable "creates a χ node for every variable in the program" unless string analysis narrows it. They did *not* implement HSSA's scaling devices (virtual variables, zero versioning, the hash), and say they would be needed to scale. They also considered Array SSA and judged HSSA "a better match", while believing either would work.

**Conclusion (p. 295).** "SSA cannot be used [as] an end-to-end intermediate representation for a PHP compiler", because substantial analysis must run first, even though the dangerous features are rarely used in hard ways.

**For chalk (my mapping).** Perl has every one of these: references and aliases (`\$x`, `foreach` aliasing, `@_`), symbolic references and `eval STRING`, `tie` and overloading as the equivalent of object handlers, plus `local`. Chalk's split (plain lexical scalars as SSA values, everything else in memory) is this chapter's "address-taken" rule applied at the declaration; it is sound only if a lexical that is captured or has a reference taken is moved to the memory side.

## What the book says about representing memory in SSA

The draft has no single chapter on this and the HSSA chapter is missing, so this section assembles the pieces. There are, in effect, five options on a ladder from crude to fine.

### The problem, as the book states it

Section 10.6 (p. 147): SSA gives the data flow between scalar variables, but "execution order of side effect instructions must also be respected." The crude approach is an ordering edge between any two consecutive instructions that may touch the same memory. With `*p = ...; *q = ...; ... = *p; ... = *q` and p, q possibly aliased, that is four links for four statements, and it grows quadratically. Hence "the usefulness of generalizing SSA and its φ-node for scalars to handle memory access for sparse analyzes": give memory a version name, and each statement names one version.

Then the caution, which no other chapter states: combining early "is well suited for analysis or interpretation", but a memory phi "might add a control dependence to an instruction that would not exist otherwise." The example is `for i { A[i] = f(A[i-2]) }`. Giving `A` a loop phi makes it easy to prove "all elements stay non-negative", but hides the fact that iterations i and i+1 are independent. A memory chain is a *conservative ordering*: good for correctness and for sparse analysis, costly for reordering.

### Option 1: keep it out of SSA

Section 19.1: variables that may be aliased "are not renamed into SSA form ... do not possess any SSA properties, and pessimistic assumptions must be made." Simple and always correct; no analysis can see through a store. This is where a compiler is before it has a memory model.

### Option 2: one state value for everything (the VSDG state edge)

Chapter 12: every load, store and call takes the current state and produces a new one; the function's exit depends on the final state. One chain covers memory, I/O and termination. Section 10.5 says the same from the array side: "For weakly-typed languages such as C, the entire heap can be modeled as a single heap array."

- *Gain:* one rule, trivially sound, dead-code elimination is a backward walk from the exit.
- *Cost:* everything effectful is totally ordered. Two writes to unrelated hashes cannot be swapped; a read cannot move past any write.
- *Stores as nodes:* in the VSDG the load or store node itself yields the state ("compute a value and state"). There is no separate version object.

### Option 3: per-location versions with may-define and may-use (HSSA)

From the draft's own words: µ and χ represent "may uses and may definitions respectively" (p. 292); they "completely model" aliasing (p. 133); HSSA also has "virtual variables", "zero versioning" and a value-numbering hash (p. 292).

*From my knowledge of the original HSSA paper (Chow et al., 1996), not from this text:* a χ on variable `v` reads `v_old` and defines `v_new`, meaning "after this statement `v` is either changed or still the old value"; it is how a store through a pointer, or a call, is recorded against every variable it might touch. A µ marks a statement as possibly reading the current version. Virtual variables are invented names standing for "whatever `*p` refers to", so indirect locations can be versioned too. Zero versions collapse the many versions nobody actually reads. Read the published chapter before relying on this.

- *Gain:* unrelated locations have unrelated chains, so reads move freely past writes that cannot touch them.
- *Cost:* needs alias analysis first, and a write that might touch anything puts a χ on everything (Chapter 19's variable-variable case).

### Option 4: memory split into disjoint arrays, each an SSA value (Array SSA, heap arrays)

Chapter 14. Partition memory into pieces that provably cannot overlap (one per field, one per element type) and version each piece. Inside a piece, a write is "element write plus dφ with the old version", a read names a version and an index, and precision comes from DS/DD on indices.

- *Gain:* element-level reasoning. Store-to-load forwarding, constant elements, redundant-load removal, all by ordinary sparse propagation. Size stays linear in the size of scalar SSA (p. 147).
- *Cost:* the partition must be *truly* disjoint. The chapter leans on strong typing for that. Precision depends entirely on how good DS and DD are.

### Option 5: promote it out of memory

Section 9.4. Once versions exist, loads and stores are just expressions for redundancy elimination: a store defines a version, loads in that version reuse the stored value, an overwritten store with no read between is dead. The end state for a location nobody else can see is that it stops being memory at all and becomes an ordinary SSA value.

### A point every chapter agrees on

A write that does not replace the whole thing is modelled as **reading the old version and producing a new one**. Array SSA's dφ takes `A0`. The ψ function takes the previous value. The status-register rule says a partial update "should appear as reading and writing". HSSA's χ takes the old version. That is the memory-chain discipline, arrived at four times independently.

### Which to choose when (my synthesis; the book does not give a decision table)

| Situation | Option |
|---|---|
| No alias information yet; correctness first | 2: one chain |
| Some classes of location provably cannot overlap | 4 with a coarse partition: one chain per class |
| Per-location alias sets from an analysis | 3: μ/χ per location |
| Element-level facts wanted inside one container | 4 in full: dφ plus DS/DD |
| A location is provably private | 5: turn it into SSA values |

These stack. Each step up needs strictly more analysis and is a refinement of the one below, so starting at option 2 does not close off the others.

## Relevance to chalk / B::SoN

Everything in this section is my reading of how the book applies; the book does not discuss sea of nodes or Perl.

### Adopt now (approach 2: one memory chain from MemStart)

- **It is a design the book documents.** One chain is the VSDG's state edge and Array SSA's "entire heap as a single heap array". Memory Phi at joins is the control phi of Chapter 14.
- **Every write takes the previous memory version as an input and produces the next.** This is the dφ/χ/ψ rule above. It also means a write can never be a leaf: it has a memory input by construction.
- **Explicit Store/Load versus effectful nodes as versions: the book shows both and they are equivalent.** Array SSA writes it as two things (`A1[k] = v` then `A2 = dphi(A1, A0)`); the VSDG and HSSA attach the new state to the effectful statement itself. Collapsing Chapter 14's pair into one node `Store(mem, key, val) -> mem'` loses nothing. For Perl, where many ops write (`push`, `delete`, `local`, a sub call), "any effectful node may produce a memory version" is the VSDG reading and avoids inventing a Store for each. If explicit Store/Load is chosen instead, the later Array SSA layer maps on one to one. Either is defensible from the text.
- **Reads name the version they see.** A Load then has (memory version, address) as inputs. With hash-based value numbering (section 9.5), two Loads with the same two inputs get the same number, so redundant-load elimination comes for free, and it is automatically blocked by any intervening write because the version differs. This is Chapter 14's index propagation in its crudest form.
- **The structural invariant.** Two sources support making it a checked invariant, not a convention: section 15.1.5 (decide what is invariant, keep it true across every pass) and Chapter 6 (prefer forms where the rule holds by construction). A concrete check taken from Algorithm 12.1: walk backwards from the End node along value and memory edges; every node whose effect signature says "writes memory" must be reached *through its memory output*. A write not on that path is exactly the "floating off the chain" bug, and in the VSDG it would be silently deleted as dead. Chapter 19's per-statement sets (must-define, may-define, use) suggest the other half: give every node kind a declared effect signature, and have the checker compare signature against edges.
- **Build memory with the same code as variables.** Treat memory as one more variable in the Chapter 5 search-based construction; memory Phis appear at joins and loop headers and trivial ones are removed by the same rule.
- **Fix for "typed by use instead of declaration".** Chapter 11: plain SSA supports hanging a fact on a value only when the fact comes from the definition. Type the SSA value from its declaration or defining node. A fact learned from a use, or from a branch condition, belongs on a *new* name that begins at that use or branch. For T1's intervals, split at conditionals (e-SSA). Fig. 11.5 is the checklist of which analysis splits where.
- **Pure nodes float; effectful ones do not.** Chapters 8 and 16 draw the line in the same place. A node that can `die` is not speculable even if it writes nothing.

### On the open questions

- **One chain or alias-class slices?** Start with one. Slices are option 4 with a coarse partition, and the book's condition for them is real disjointness. Perl makes that harder than Java: `\$a[0]` yields a scalar reference to an array element, `foreach` and `@_` alias elements, and `tie` can run arbitrary code on access. So "array elements", "hash elements" and "scalar cells" are *not* disjoint classes in general. A safe first split is by *what can be proved unreachable from references*, which is an escape-analysis result. A write through an unknown reference must then advance every slice it might touch, which is a χ on each.
- **I/O and die ordering separate from memory?** The book offers only the combined form: the VSDG state edge mixes memory order, I/O order and termination, and Chapter 6's note on monadic languages treats all effects uniformly. Nothing in the text argues against separating them, and nothing shows it done. The dependences are separable in principle: `print` must be ordered against other I/O and need not be ordered against a hash store. The risk to watch is Chapter 19's: in Perl a `print` on a tied handle, or a `die` with a `__DIE__` handler, runs arbitrary code, so the separate chains must be joined at any node that might do so.
- **Whole-program analysis.** Chapter 19's demand for whole-program alias analysis before SSA is about precision, not soundness: chalk's declaration-based rule gets a sound SSA without it, at the price of treating all memory as one thing.

### Save for the later Array-SSA / escape-analysis layer

- Chapter 14's partial Array SSA as the model for `update(a, i, v)`: dφ, the `(index, value)` list lattice, the UPDATE rule that drops pairs not definitely different, the control-phi intersection, and the list-length cap.
- DS from value numbering; DD from allocation sites (two rules, p. 210). These two rules are a minimal escape-style fact and a good first target for the reference-flow analysis.
- Heap arrays per field as the eventual slicing scheme; for Perl the analogue would be per container once the container is known not to be aliased.
- Section 9.4: load PRE then store PRE, stores as version definitions, dead-store removal as the mirror problem.
- Chapter 8's chains of recurrences for loop-index intervals and for DD on subscripts like `i` and `i+1`.
- The 10.6 caution: a per-array chain still serialises a loop's iterations. If chalk ever wants loop-level reordering, the memory phi is what stands in the way.
- In-place update when the old version is unique is *not* in this book; look to the functional-array and uniqueness literature for that.

### Does not apply, or is LLVM's job

- Leaving SSA, liveness, copy merging, register allocation (Chapters 3 second half, 7, 15, 17): LLVM does these.
- Predicated machine code, if-conversion, hardware (13, 16, 18).
- Faster phi placement for CFG-based builders (4).
- Full Array SSA with @ timestamps: a run-time parallelisation device.
- Gated SSA and the PDG: B::SoN already keeps control as edges.

## Where to read more

In priority order for the memory-model question. Printed page numbers; add 14 for the PDF page.

1. **Chapter 14, Array SSA Form, pp. 199-213.** All of it. Sections 14.1 (skip the @-variable detail on first reading) and 14.3 matter most.
2. **Chapter 12, section 12.5, Value State Dependence Graph, pp. 178-183**, then the further readings on p. 184 for the VSDG papers. The closest thing to sea of nodes in the book.
3. **Chapter 10, pp. 143-148**, especially 10.5 and 10.6. Five pages; the only place the trade-off of memory phis is stated.
4. **Chapter 19, Building SSA in a Compiler for PHP, pp. 285-296.** Short, plain, and about a language like ours.
5. **Chapter 11, sections 11.1.1 and 11.1.3 to 11.1.6, pp. 150-160, plus Fig. 11.5 on p. 161.** For the typing bug and for intervals. Skip the formal definition on p. 152 at first.
6. **Chapter 9, sections 9.4 and 9.5, pp. 131-138.** Loads, stores, value numbering.
7. **Chapter 5, pp. 59-66.** The construction algorithm in the Click/Braun family.
8. **Chapter 8, section 8.1, pp. 111-114.** SSA without a CFG and why loops need exit phis.
9. **Chapter 15, sections 15.1.4 and 15.1.5, pp. 223-225.** Non-killing definitions and invariants.
10. **Chapters 1 and 2, pp. 5-25.** If the vocabulary is unfamiliar.

Not in our copy, and worth getting from the Springer edition: the **Hashed SSA (HSSA)** chapter (μ, χ, virtual variables, zero versions: option 3 above in full) and **Propagating Information Using SSA** (the sparse propagation engine and conditional constant propagation that T1's analyses are instances of). The original papers are Chow et al., "Effective representation of aliases and indirect memory operations in SSA form" (1996), cited in the draft as [59], and Wegman and Zadeck on conditional constant propagation.
