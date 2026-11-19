# Simple and Efficient Construction of Static Single Assignment Form

**Authors, venue, year.** Matthias Braun, Sebastian Buchwald, Sebastian Hack, Roland Leissa, Christoph Mallon, Andreas Zwinkau. International Conference on Compiler Construction (CC), 2013.  **Source:** https://bernsteinbear.com/assets/img/braun13cc.pdf

*What I read and how: all 20 pages from the extracted text (clean): Sections 1-8 including the proofs of Section 4, both applications in Section 5, and Tables 1-3. Figures 3 and 6 are drawings; I relied on their captions and the prose that walks through them.*

## In one paragraph

The textbook way to build SSA (Cytron et al.) needs a finished control-flow graph in non-SSA form, a dominator tree, dominance frontiers and, to avoid dead Phis, a liveness analysis. This paper shows you need none of that. You can go straight from a syntax tree (or bytecode, or perl's op tree) to SSA in one walk by answering a single question lazily: "what is the current value of variable `v` at this point?" If the answer is not known locally, ask the predecessors; if there are several predecessors, make a Phi. The result is always in SSA form, even half-built, so optimisations can run during construction. The authors prove the output is pruned and (for ordinary control flow) minimal, and their LLVM implementation is as fast as LLVM's tuned Cytron implementation. Cranelift's frontend uses this algorithm.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Terms.** A *Phi* at a join point selects the value from whichever predecessor control arrived from. *Minimal* SSA has no Phis that could be avoided; *pruned* SSA has no Phis whose value is never read. A control-flow graph is *reducible* when every loop has one entry (true of structured code without `goto` into loops).

**Work backwards from uses.** Cytron works forwards from definitions ("this variable is assigned here, so where might a merge be needed?"). Braun works backwards from uses ("I need `x` here; who defined it?"). Nothing is created for a variable nobody reads, which is why the output is pruned for free.

**Two states of a block.**
- *Filled*: all its instructions have been generated, so it can answer "what does `x` hold at my end?"
- *Sealed*: all its predecessors are known, so it can ask *them*.
A loop header is not sealed until the back edge from the loop body has been added.

**Break cycles by planting the Phi first.** When a block with several predecessors is asked for `x`, it creates an empty Phi, records "x is this Phi" *before* asking predecessors, then fills the Phi in. If the question comes back round a loop, it finds the Phi and stops.

**Throw away trivial Phis.** A Phi whose inputs are all the same value (or itself) is not needed: replace it by that value, then re-check Phis that used it.

Worked example:

```perl
my $x = 0;
while ($x < 10) { $x = $x + 1 }
print $x;
```

1. Entry block: `writeVariable(x, v0)` with `v0 = 0`. Entry is filled and sealed.
2. Create the loop header. It is **not sealed** (the back edge is missing). The condition reads `x`: no local definition, block unsealed, so plant an *incomplete* Phi `v1 = phi(?)`, record it as `x` here, and emit `v1 < 10`.
3. Body (one predecessor, sealed at once): reads `x`, gets `v1` from the header; emits `v2 = v1 + 1`; `writeVariable(x, v2)`.
4. Add the back edge body -> header. **Seal the header**: complete the Phi by asking each predecessor: `v1 = phi(v0, v2)`. Not trivial; it stays.
5. Exit block reads `x`: single predecessor (header) gives `v1`.

```
v0 = 0
header:  v1 = phi(v0, v2);  if !(v1 < 10) goto exit
body:    v2 = v1 + 1;       goto header
exit:    print v1
```

Had the body not assigned `$x`, step 4 would give `v1 = phi(v0, v1)`, which is trivial; `v1` would be replaced by `v0` everywhere.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** the source in execution order; the ability to create blocks and edges as you go. No prior analysis.

- `writeVariable(var, block, value)`: `currentDef[var][block] = value`.
- `readVariable(var, block)`: return `currentDef[var][block]` if present (this is *local value numbering*), else `readVariableRecursive`.
- `readVariableRecursive(var, block)`:
  - block **not sealed**: create an operandless Phi, remember it in `incompletePhis[block][var]`;
  - block sealed with **one predecessor**: recurse into it, no Phi;
  - otherwise: create an operandless Phi, `writeVariable` it (cycle breaker), then `addPhiOperands`.
  In all cases `writeVariable(var, block, result)` to cache the answer.
- `addPhiOperands(var, phi)`: for each predecessor append `readVariable(var, pred)`; then `tryRemoveTrivialPhi(phi)`.
- `tryRemoveTrivialPhi(phi)`: if all operands are one value `same` or the Phi itself, reroute every user of the Phi to `same`, delete it, and retry on users that are Phis. (Needs a list of each Phi's users.) A Phi with no real operand at all means "undefined".
- `sealBlock(block)`: complete every incomplete Phi of the block, mark it sealed.

**Irreducible control flow.** Trivial-Phi removal alone can leave a ring of Phis that all carry one outside value. A post-pass finds strongly connected groups of Phis (Tarjan's algorithm) and collapses any group with a single outside input. With it, the result is minimal for arbitrary control flow.

**On-the-fly optimisation.** Because the IR is valid SSA throughout, node constructors can fold constants, simplify arithmetic, eliminate common subexpressions and propagate copies as nodes are made.

**Complexity.** With P program size, B blocks, E edges, V variables: Theta(P + (B+E)·V) for the basic algorithm, which matches the lower bound; on-the-fly trivial-Phi removal is bounded by O(B²·V²); the minimality post-pass gives O(P + B·(B+E)·V²) overall.

**Details the pseudocode leaves implicit.**

- *Order of sealing in a `while`* (Figure 3): create the header, add the edge from the entry block, do **not** seal it; create body-entry and exit blocks; seal body-entry at once; build the body; add the back edge; seal the header; finally seal the exit block (it could not be sealed earlier because `break` statements in the body may add predecessors to it).
- *Only filled blocks may have successors*, so every predecessor a lookup recurses into is complete.
- *Witness caching.* A Phi remembers two operands that differ from each other and from itself as proof it is not trivial; a re-check only has to confirm they still differ.
- *No user lists?* A simpler variant re-checks the Phi's unique *operand* rather than its users. It gives minimal SSA "for most but not all cases" and suits IRs that do not keep def-to-use lists.
- A Phi left with no operand other than itself is "either unreachable or in the start block" and is replaced by an `Undef` value.

**Fewer temporary Phis (Section 3.3).** The *marker algorithm* marks a block as "being visited" instead of planting a Phi, and only creates one if the recursion comes back to the mark or the predecessors return different values; in loop-free regions no temporary Phi is ever made. The *SCC variant* runs Tarjan's algorithm during the recursion to spot data-flow cycles; if a single value enters the cycle no Phi is placed.

**On-the-fly optimisation example (Figure 4).**

```c
int mask = 0; int res;
if (x & mask) { res = 0; } else { res = x; }
return res;
```

`x & 0` simplifies to the existing constant 0; `0 != 0` folds to false; the `then` arm is never built; `res` is just `x`; no Phi is needed; the function becomes `return x`. That is fewer Phis than Cytron's definition of minimal.

**Why the result is pruned and minimal (Section 4).**

- *Pruned* (every Phi eventually feeds a non-Phi user): Phis are only made when a read, or another Phi, asks.
- *Minimal on reducible graphs.* A Phi is *necessary* in block Z if two paths starting at different blocks that assign the variable first meet at Z. The *SSA property*: no path from a definition to its use passes another definition of the same variable. Lemma 2: two different operands of a Phi cannot both sit in blocks that dominate the Phi's block (one would hide the other). Lemma 3: an unnecessary but non-trivial Phi has an operand that is itself an unnecessary Phi in a block that does *not* dominate it. Theorem 1: follow that operand chain; the program is finite so it must loop; a loop of Phis lies on a loop of blocks; in a reducible graph that loop has one entry block dominating the rest, and the Phi there dominates the others, contradicting Lemma 3.
- *Irreducible graphs (Section 3.2).* Example: a `goto` into the middle of a `while` gives two Phis `v1 = phi(v0, v2)`, `v2 = phi(v0, v1)` though `x` has one definition. A set of Phis is *redundant* if they refer only to each other and one outside value; Lemma 1 shows any such set contains a strongly connected component (a group where each member reaches every other) that is redundant. Algorithm 5 computes these groups, processes them in dependency order, replaces a group with a single outside operand by that operand, and otherwise recurses on the Phis whose operands are all inside the group. The paper notes copy propagation can create the same pattern after *any* construction algorithm, so this pass is generally useful.

**Evaluation (Section 6, Tables 1-3).** Implemented in LLVM 3.1 (Clang), C programs of SPEC CINT2000, Core i7-2600.

- *Table 1, IR size.* Before SSA construction the suite has 1,245,933 instructions, of which 549,174 are memory instructions (alloca/load/store) and 9,754 Phis. After LLVM's Cytron-based pass: 934,392 instructions, 208,713 memory, 38,674 Phis. After the marker algorithm: 931,865 / 208,583 / 38,696. So SSA construction removes 25% of instructions, "which demonstrates the significant overhead of the temporary non-SSA IR". Differences between the two algorithms: 3 of 11 non-trivial redundant Phi groups did not come from irreducible flow and are not removed by Cytron's algorithm; the rest is unreachable-code handling and extra constant folding.
- *Table 2, speed*, measured as x86 instructions executed (valgrind): Cytron 71,846,356,773; marker 71,647,089,583, i.e. 99.72% (per benchmark 98.50% to 100.28%). An untuned implementation is level with LLVM's "highly-tuned" one.
- *Table 3, on-the-fly optimisation in libFIRM.* Without: 147.67 s total, 2.01 s IR construction, 974,743 nodes. With: 146.18 s, 2.86 s, 859,311 nodes. Construction is 0.84 s slower, the graph is 88.2% the size, the whole compile 1.49 s faster.

**Other applications (Section 5).**

- *SSA reconstruction.* After a transformation adds a second definition of an SSA value (jump threading, live-range splitting, rematerialisation), call `writeVariable` for each definition under one handle and `readVariableRecursive` at each use; needed Phis appear. No dominance recomputation, which matters because jump threading runs repeatedly.
- *CPS construction.* The same algorithm builds continuation-passing style: block parameters instead of Phis, call arguments instead of Phi operands. Removing a "Phi" is costlier there (a parameter and all call sites change).

**Related work (Section 7).** Choi et al. get pruned SSA from Cytron by adding liveness analysis; Briggs et al.'s semi-pruned form avoids liveness but only helps variables local to one block; Sreedhar and Gao's DJ-graphs give linear-time placement per variable; Brandis and Mössenböck work on the syntax tree but only for structured code and not pruned; Click and Paleczny's construction is "in the spirit" of Brandis and Mössenböck and gives neither pruned nor minimal SSA; Aycock and Horspool put a Phi for every variable in every block and then simplify, which is minimal for reducible programs but wasteful.

## Memory, arrays, aliasing (what it says, or "not addressed")

Not addressed. The algorithm handles named local variables only. Memory appears only in the observation that LLVM models locals as stack slots with load/store before promotion.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Adopt as B::SoN's construction algorithm.** Perl's op tree is walked in execution order and its loops and conditionals are structured, so sealing points are obvious: seal an `if` join after both arms, a loop header after the back edge (and after every `next`/`redo` edge), a loop exit after every `last`.
- **Memory as a variable.** Give "current memory" a slot in `currentDef` like any lexical. A write node does `writeVariable(MEM, block, newVersion)`; a read does `readVariable(MEM, block)`. Memory Phis then appear exactly where two different memory versions meet, and are removed as trivial where a branch did not write. The same works for an I/O chain. This gives one code path for scalars and memory. (Inference: the paper does not discuss memory; libFIRM, by the same authors, works this way.)
- **Structural invariant.** If the *only* way to obtain a memory input is `readVariable(MEM, ...)` and every writing constructor is obliged to `writeVariable(MEM, ...)`, a write cannot float off the chain at construction time. Later passes need the verifier. (Inference.)
- **Loop headers are the danger spot.** A read inside a loop before the header is sealed gets an incomplete Phi. If B::SoN forgets to seal, or seals before adding a `next`/`redo` edge, the Phi is missing an input: for a scalar that is a wrong value, for memory it is a lost write.
- **Typing by declaration.** `currentDef` is keyed by declared variable (pad entry), and each definition is one node. Attach the declared kind (scalar/array/hash, lexical/package/captured) to the variable key at `my`/pad time, not to each use site.
- **"Undefined".** A Phi with no real operands signals a read with no reaching definition. In Perl that should not happen for `my` variables (they start as `undef`); if it does, it is a B::SoN bug worth asserting on.
- **Perl features that need care:** `goto LABEL` and loop control that jumps across nested blocks can make flow irreducible, where the SCC post-pass is needed for minimality (correctness is unaffected). Closures: captured variables live in memory in chalk's model, so they do not go through `currentDef`.

## Limits and later work

Recursion depth can be large on long chains of single-predecessor blocks (implementations iterate or cache). Trivial-Phi removal needs def-to-use information for Phis. Minimality on irreducible graphs needs the extra pass. No story for memory or aliasing. Formally verified later (Buchwald, Lohner, Ullrich, "Verified construction of static single assignment form", CC 2016; my addition, not in this source). Lemerre's "SSA Translation Is an Abstract Interpretation" and the lambda-G paper both cite it as the standard dominance-free construction.
