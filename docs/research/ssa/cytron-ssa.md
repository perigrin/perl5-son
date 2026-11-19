# Efficiently Computing Static Single Assignment Form and the Control Dependence Graph

**Authors, venue, year.** Ron Cytron, Jeanne Ferrante, Barry K. Rosen, Mark N. Wegman (IBM Research Division), F. Kenneth Zadeck (Brown University). ACM Transactions on Programming Languages and Systems, vol. 13 no. 4, October 1991, pages 451-490. A preliminary version appeared at POPL 1989. **Source:** https://bernsteinbear.com/assets/img/cytron-ssa.pdf

*What I read and how: the whole paper, sections 1 to 9 (40 pages), from the extracted text, which for this scan is good: prose, lemmas, proofs and all the pseudocode figures (10, 11, 12, 14, 17) are readable, with scattered misread symbols. Diagrams (Figures 5, 9) and the three scatter plots (20 to 22) do not survive as text; I took their content from the surrounding prose and captions and did not render the pages. I did not read the reference list in full.*

## In one paragraph

This is "the Cytron paper", the standard reference for building SSA. Earlier work knew what SSA was but not how to build it cheaply for arbitrary control flow with the fewest phi functions. This paper answers with one new concept, the *dominance frontier*, which says exactly where an assignment stops being "the only possible value" and a merge is needed. It gives the algorithms (frontiers, phi placement, renaming), proves the result minimal and correct, reuses the same machinery on the reversed graph to compute *control dependence*, shows how to get back out of SSA, and measures everything as effectively linear on real Fortran. A short section on arrays, structures, pointers and calls is the part closest to chalk's current design question.

## Key ideas

**Why SSA** (section 1). With ordinary names, a variable with D definitions and U uses can need D x U def-use links; in SSA each use has one definition and the links are bounded by the number of control flow edges. The paper's motivating client is constant propagation that also discovers dead branches: because a phi's operand is tied to one incoming edge, an operand arriving on an edge not yet known to be executable can be ignored.

**SSA and phi** (section 3). An assignment is `LHS = RHS`, where both sides may be *tuples* (lists), so one statement can assign several variables. A program is in SSA form if every variable is the target of exactly one assignment in the text. At a join, `V3 = phi(V1, V2)` has one operand per control flow predecessor, in a fixed order; operand j is the value if control arrived from predecessor j. All phis at the top of a block run before its ordinary statements. Three conditions define a correct translation: a phi wherever two paths starting at different assignments to V converge; every mention renamed so the result is in SSA form; and each new name has the value the old variable had there. *Minimal* SSA uses the fewest phis that satisfy the first condition. *Pruned* SSA also omits phis whose result is never used; the authors prefer to keep those dead phis, since value numbering can sometimes put them to use (Figure 16).

**Dominance** (section 4.1). In a control flow graph (CFG: nodes are basic blocks, plus Entry and Exit) node X *dominates* Y if X is on every path from Entry to Y; *strictly* if also X is not Y. Y's *immediate dominator* is its closest strict dominator. Hanging each node under its immediate dominator gives the *dominator tree*.

**Dominance frontier** (sections 1.2, 4.2). Suppose X assigns V. Every node X strictly dominates is certain to see X's value. Walk outward until you reach the first node Z that X does not strictly dominate: Z can be reached some other way and might see a different value. Z is in the *dominance frontier* of X. Precisely: DF(X) is every Y such that X dominates a predecessor of Y but does not strictly dominate Y.

**Rule** (Theorem 2). The nodes needing a phi for V are the *iterated* dominance frontier of the set of nodes assigning V: take the frontier, add it to the set (a phi is an assignment), repeat until stable. The proof shows this equals the "iterated join" (where paths from two assignments converge); it relies on every variable having an assignment at Entry.

**Worked example.**

```perl
my $i = 0;                 # B1
while ($i < 10) {          # B2  (loop test)
    $i = $i + 1;           # B3
}
print $i;                  # B4
```

Edges: B1 to B2, B2 to B3, B3 back to B2, B2 to B4. B3 dominates only itself; its successor B2 is not dominated by it, so DF(B3) = {B2}. `$i` is assigned in B3, so B2 gets a phi:

```
B1: i1 = 0
B2: i2 = phi(i1, i3);  if i2 < 10 goto B3 else B4
B3: i3 = i2 + 1;       goto B2
B4: print i2
```

B4 needs no phi: B2 dominates it, so only `i2` can arrive.

## Construction / algorithm

Input: the CFG, with an edge Entry to Exit added and every variable given a nominal assignment at Entry.

1. **Dominator tree.** Lengauer-Tarjan, treated as linear time.
2. **Dominance frontiers** (Figure 10). One bottom-up pass over the dominator tree. For node X: add each CFG successor Y whose immediate dominator is not X (the "local" part); then, for each dominator-tree child Z, add each Y in DF(Z) whose immediate dominator is not X (the part passed "up"). Two equality tests, no searching. Time O(E + total size of the frontiers).
3. **Place phis** (Figure 11). Per variable V: a worklist starts with the nodes assigning V. Take X off; for each Y in DF(X) that has no phi for V yet, place `V = phi(V, ..., V)` and, if Y has not been on the worklist, add it. Two per-node stamps (`HasAlready`, `Work`) hold the current variable's number so nothing needs resetting between variables.
4. **Rename** (Figure 12). A counter and a stack per variable. `SEARCH(X)`, called on Entry: for each statement in X in order, replace each used V by the name on top of V's stack (not for phi operands), then for each assigned V make a new name, push it; for each CFG successor Y, set the operand for X in each of Y's phis to the current top of stack; recurse into X's dominator-tree children; finally pop once per assignment in X. Lemmas 8 to 10 prove each new name has one assignment and holds the right value.

**Cost** (Theorem 3, section 9.1). O(E + total frontier size + (assignments after x average frontier size) + mentions after). Worst case O(R^2) for frontiers and O(R^3) overall in program size R, entirely because the output itself can be that large.

**How big in practice** (section 8). Theorem 4: for programs built only from straight-line code, if-then-else and while-do, every dominance frontier has at most two nodes. Not so for nested repeat-until loops: n nested loops give frontiers of total size n^2 though each variable needs only about n phis. Measured on 221 Fortran procedures (EISPACK, FLO52, SPICE; 23,181 statements, chosen for their unstructured control flow): frontier size, phi count and control-dependence size all grow linearly with program size; assignments grow by 1.3 to 3.8 times, mentions by 1.6 to 6.2 times.

**Control dependence** (section 6). Y *postdominates* X if Y is on every path from X to Exit. Y is *control dependent* on X if some edge out of X makes Y certain to run while another path from X avoids it. Corollary 1: that holds exactly when X is in the dominance frontier of Y in the *reversed* CFG. So: reverse the graph, run steps 1 and 2, invert the result (Figure 14).

**Getting out of SSA** (section 7). Replace a k-input phi by k copies, one at the end of each predecessor. To make that efficient, first run **dead code elimination** (Figure 17): mark everything dead; mark live anything with visible effect (I/O, assignment to a reference parameter, a call that may have side effects); then repeatedly mark live whatever defines a value a live statement uses, and any branch that a live statement is control dependent on. Unmarked statements, including unneeded branches, are deleted. Then **graph colouring** merges SSA names that are never live at the same time, turning most copies into `V = V`, which are deleted. One cannot simply erase subscripts: after code motion two versions of V may be live at once (Figure 18).

## Memory, arrays, aliasing

Section 3.1, "Other Program Constructs".

**Arrays as values.** Treating element `A(i)` as a variable "would be awkward", because a write to `A(i)` may or may not change `A(j)`. Instead "the entire array is treated like a single scalar variable":

```
x = A(i)          t1 = Access(A8, i)
A(j) = v    =>    A9 = Update(A8, j, v)
y = A(k)          t2 = Access(A9, k)
```

(Paper's Figure 7; index subscripts omitted.) `Update(A, j, v)` returns a whole new array value equal to the old one except at index j. The write names the old version as an input and defines a new one; each read names the version it sees. "The translation to SSA form is unconcerned with whether the values of variables are large objects." Renaming also removes false ordering constraints between a read of one version and a write producing the next.

**The cost, and HiddenUpdate.** Because every `Update` uses the previous version, earlier writes look live even in a loop that overwrites the whole array. Either accept that, or use dependence analysis and record its conclusion with `HiddenUpdate(j, v)`, which omits the old-array operand. Section 7.2 closes the loop: colouring gives consecutive versions the same storage, so an `Update` becomes an in-place store of one element. No array is copied.

**Structures** are arrays indexed by constants. If the fields are always accessed disjointly, the structure "can be decomposed into n distinct variables".

**Implicit references** (calls, aliases, pointers). For each statement S: MustMod(S), MayMod(S), MayUse(S) are what it certainly writes, may write, and may read. Represent S as a tuple assignment whose left side is all of MayMod and whose right side is MayUse plus (MayMod minus MustMod). In words: a statement that *might* write a variable both defines a new version and uses the old one, because the old value may survive. An unanalysed call has all globals on both sides, represented compactly by a flag.

**Heap.** "Heap storage can be conservatively modeled by representing the entire heap as a single variable that is both modified and used by any statement that may change the heap." The paper adds that this "is already strong enough to support optimization of code that does not involve the heap but is interspersed with heap-dependent code".

## Relevance to chalk / B::SoN

- **The proposed memory design is this paper's conservative heap model.** One memory variable; a write is `mem2 = Update(mem1, ...)`; a read is `Access(mem1, ...)`; Phi merges memory at joins. The quoted sentence about interspersed code is what chalk needs first: plain lexical scalars optimise well while containers stay conservative. (The correspondence is my reading; the paper does not discuss sea-of-nodes.)
- **The MayMod rule is the test for the known bug class.** Every operation that may write memory takes the current memory version as input and produces the next. A list assignment into `$a[0]` that produces no new version is a statement with a non-empty MayMod set and an empty left side: later reads see a version that predates the write.
- **`my @rest` and HiddenUpdate (my inference).** A fresh array feels as if it has no previous version, which is the `HiddenUpdate` situation. That shortcut is valid only when the array is its own SSA variable. With a single memory chain the allocation still consumes and produces memory, because the chain carries everything else too. Dropping the input is what makes the node float.
- **Tuple assignments fit Perl.** `($a, $b) = ($b, $a)` is literally the paper's `LHS = RHS` with 2-tuples: all right sides are read before any left side is written. A list assignment whose targets include an array element is a tuple whose left side includes memory (my application).
- **The live-marking rule guards writes.** Dead code elimination starts from "statements assumed to affect output", which include calls with side effects and assignments through references. In chalk, a store whose memory output nobody consumes looks dead under rule 2. So a floating write is not only invisible to later reads; it is a candidate for deletion (my inference).
- **Calls.** A call to a sub chalk cannot see into uses and defines memory.
- **Array SSA later.** Structure decomposition is the paper's version of chalk's deferred escape-analysis step, and section 7.2 says value-style arrays need not cost copies once versions share storage.
- **Control dependence** is what a sea-of-nodes graph encodes when a node takes a control input: the paper's reversed-graph construction is the batch way to compute it (my comparison).
- **Placement machinery.** Dominance frontiers need a finished CFG and assignment lists. A backend building directly from the op tree will more naturally use a single-pass method (Brandis and Mössenböck); Theorem 4 says why that is safe to expect to be small for if/while code. The dominance-frontier definition remains the specification any shortcut must match, and `do {} while` nests are the case to test (my inference).

## Limits and later work

- The paper's own related work: minimal SSA refines Shapiro and Saint's "pseudoassignments" (1970); a closer precursor (Cytron-Lowry-Zadeck) used new names without explicit phis; Reif-Tarjan and Rosen-Wegman-Zadeck gave earlier algorithms that are inherently quadratic or limited to reducible graphs.
- Minimal SSA has dead phis; pruned SSA needs liveness analysis. Briggs et al. add *semi-pruned* SSA as a cheaper middle, speed up renaming, and show that the "one copy per predecessor" exit from SSA, which this paper calls "always correct", breaks once copies are folded or critical edges are left unsplit.
- Frontiers can be quadratic (nested repeat-until). Sreedhar and Gao place phis in linear time without precomputing them.
- The algorithm is exhaustive: any change means a rebuild. Choi, Sarkar and Schonberg give incremental updates.
- Brandis and Mössenböck, and Aycock and Horspool, give simpler constructions for structured or reducible programs. Nguyen and Scholz recast the three relations as Boolean matrix equations.
- The `Update`/`Access` model is deliberately crude; the paper points to dependence and alias analysis for anything finer.
