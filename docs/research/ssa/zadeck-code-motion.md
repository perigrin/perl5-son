# Code Motion of Control Structures in High-Level Languages

**Authors, venue, year.** Ron Cytron, Andy Lowry, Kenneth Zadeck (IBM T. J. Watson Research Center; Lowry's current address is given as Columbia University). ACM, 1986, pages 70-85. The paper itself carries only the ACM 1986 copyright line; the venue is confirmed by the reference lists of two other papers in this set (Rosen-Wegman-Zadeck and Sreedhar-Gao), which cite it as *Conference Record of the Thirteenth Annual ACM Symposium on Principles of Programming Languages* (POPL), January 1986. **Source:** https://bernsteinbear.com/assets/img/zadeck-code-motion.pdf

*What I read and how: all 16 pages, as page images rendered from the PDF at 120 dpi (the extracted text is a two-column OCR with interleaved lines and was used only for searching). Body text, footnotes, and Figures 2 to 9, 11 and 12 were legible. Figure 10 (a 30-node graph) was legible as a picture but I followed its walkthrough from the prose, not by checking every node.*

## In one paragraph

This is a paper about moving code out of loops ("code motion"), motivated by programs built from layers of abstractions: once procedure calls are inlined, the loops are full of `if` tests that hide movable code. It is written before the term SSA existed, and its lasting contribution is a preparatory step called RENAME: give every value of every variable its own temporary name, and mark the places where different values of the same variable meet. Those meeting places are called *join birthpoints*, and they are what later papers call phi functions. On top of the renamed program the paper builds four algorithms (STRICT, COMMON, NONSTRICT, COMBINE) that move statements *together with the control structure that guards them*.

## Key ideas

**Four things earlier methods did not handle together** (section 1): some code can only move if its surrounding `if` moves too; stores should move as well as expressions; it can pay to move code from where it might not run to where it always runs; and moving one thing may enable moving another ("second order effects").

**Vocabulary** (section 3).

- An *interval* is a loop: the strongly connected region dominated by its header (the single entry).
- A *landing pad* is an empty block added just outside a loop to receive moved code: one *entry pad* before it, one *exit pad* per exit. The loop's entry test is duplicated so the entry pad runs only if the loop would have (turning `while` into `if` around `repeat ... until`).
- *Strict* motion never makes code run more often than before. *Nonstrict* motion may run something that the original would have skipped, betting that once per loop entry beats many times inside. *Correctness* means values still come from the same computations. *Safety* (which statements may be moved at all, for example ones that might trap) is left to the compiler writer.
- *Dominated topological order*: visit a loop body's blocks so that every block comes after its predecessors, and everything a block dominates comes before anything else that follows it.

**Naming values, not slots** (section 4.1). A source variable such as `$k` is one name for many values. If the compiler only knows the name, every assignment to `$k` must stay in order. If each assignment gets its own name, unrelated ones may move. The paper's term is *birthpoint*: "a single use of a variable may be reached by several definitions ... a use is reached by exactly one birthpoint". The graph is divided, per variable, into maximal single-entry regions whose nodes all see the same set of definitions; the entry of each region is a birthpoint. There are two kinds:

- a *definition birthpoint*: an ordinary assignment;
- a *join birthpoint*: where different birthpoints of the same variable arrive on different incoming edges.

**Worked example** (the paper's Figures 3 and 4, cut down). Source:

```
while (i < n)
    if n > 3 then k = n * 6
             else k = n * 8
    j = k + 3
    i = i + 1
```

After RENAME (the paper writes new names as `k.3`):

```
entry pad:  i.1 = i;  k.1 = k;  n.1 = n          # identity assignments: values entering the loop
loop:       birthpoint i.2;  birthpoint k.2      # entering value meets the value from the back edge
            if n.1 > 3 then  k.3 = n.1 * 6;  k.5 = k.3
                       else  k.4 = n.1 * 8;  k.5 = k.4
            birthpoint k.5
            j.3 = k.5 + 3
            i.3 = i.2 + 1;   i.2 = i.3
exit pad:   i = i.3;  j = j.3;  k = k.5          # hand values back to the source names
```

There is no phi symbol. The join is a marker, `birthpoint k.5`, and each branch ends with a copy into it (`k.5 = k.3`, `k.5 = k.4`). A modern reader writes `k.5 = phi(k.3, k.4)`.

## Construction / algorithm

Input: a control flow graph divided into loops, processed innermost first; after a loop is processed it is summarised and treated as one statement of the enclosing loop.

**RENAME, four transformations** (section 4.1.1):

1. *Separation.* Put an identity assignment `x = x` in the entry pad for every variable used or defined in the loop. Split every assignment into `x.n = expr; x = x.n`, so the computing half can move independently of the defining half.
2. *Join birthpoints.* Add one at the loop header for each variable defined in the loop. Then visit the body (a cycle-free graph once the back edge is ignored) in topological order: if all of a block's predecessors are covered by the same birthpoint, so is the block; otherwise create a join birthpoint there. Each is written as `x.n = x; x = x.n`. For arbitrary graphs the paper points to Reif and Tarjan.
3. *Forward substitution* of the new names into the uses they cover.
4. *Back substitution.* Remove the remaining assignments to source names (dead ones are deleted; the others become copies into the birthpoint name), leave a *birthpoint marker*, and add assignments back to the source names in each exit pad.

When every loop has been processed, no source names remain. A definition of the special value *uninitialized* at program start keeps the meaning of uninitialised variables. Afterwards, dead-code elimination removes unused temporaries, and register-allocation "coloring" (Chaitin) merges the rest.

**STRICT** (section 4.2). One pass over the loop body in dominated topological order. Tests that can be decided before the loop are copied into the entry pad (and replaced inside by a test of a saved bit); movable statements go under the copied tests. A statement may move if (1) it is not *control dependent* on an immovable test (control dependent: the test decides whether it runs); (2) every definition reaching its uses comes from outside the loop; (3) for a definition, the variable's birthpoint has not yet been processed and no earlier definition of it was immovable. Join birthpoints at the top of a loop never move.

**COMMON** (section 4.3). "Structural common subexpression elimination": if the same assignment appears on *every* branch of an immovable test, hoist one copy above the test. Because renaming gave the copies different targets, the targets are merged in an *aliasing dictionary* (a union-find structure) so later matches see them as one name. Extended to whole `if` structures, restricted to regions that are single-entry single-exit "series-parallel" shapes, as in structured code.

**NONSTRICT** (section 4.4). Also moves statements guarded by immovable tests, executing them unconditionally in the entry pad, under extra conditions (their inputs come from outside or from other moved code; the moved definition is the only one reaching its uses). Figure 10 walks a 30-node example.

**COMBINE** (section 4.5). A dictionary of expressions already executed unconditionally in the pad, so NONSTRICT does not duplicate them.

**Cost.** No time bound is given for RENAME. COMMON has "a heuristic component that limits its effectiveness to obtain a polynomial time bound". Worst-case code growth is a factor of 2^d for loop nesting depth d (every control structure copied at every level), which the authors call unlikely and controllable by limiting how deep the optimisation is applied.

## Memory, arrays, aliasing

Restricted, and said so more than once:

- "These transformations are restricted to scalars where the pattern of aliasing is understood. No reordering can be done on variables that are potentially aliased, because the real patterns of loads and stores for those variables are unknown."
- Array elements may be treated as scalars when subscript analysis (Banerjee, Wolfe, Allen) proves two references are always distinct.
- Footnote 3: the renamed form summarises definitions and uses "but requires a worst case assumption with respect to MAY. This assumption is that a MAY site both USEs and DEFs the variable."
- Footnote 6, on external variables: "Each nonintegrated subroutine call must be treated as a birthpoint for all external variables. Stores for these variables are still required before any external subroutine call. After the subroutine call, a reference must be made that resets the appropriate temporary variable."
- "The motion of stores should be considered as well as the motion of expressions" is one of the paper's four goals; splitting each assignment in transformation 1 is how a store is separated from the computation feeding it.

## Relevance to chalk / B::SoN

- **Adopt the framing.** "Name the value, not the slot" is why chalk keeps plain lexical scalars as SSA values. The join birthpoint is chalk's Phi; the header birthpoint is a loop Phi.
- **The scalar/aliased split matches chalk's.** Only variables whose aliasing is understood are renamed; the rest stay as loads and stores. That is the line chalk draws between lexical scalars and everything that lives in memory.
- **Footnotes 3 and 6 are the rule the known bug class breaks (my inference for chalk; the rule is the paper's).** Anything that *might* write is both a use and a definition, and a call to code the compiler cannot see is a birthpoint for every external variable, with values stored before the call and re-read after. In chalk's terms: every possible write, and every call to unknown Perl code, consumes the current memory version and produces a new one, and package variables are re-read afterwards. A list assignment into `$a[0]` that produces no new memory version is a MAY site treated as nothing.
- **Entry-pad identity assignments** are the same device as giving every variable (and memory) an explicit starting definition, which chalk's MemStart already is (my comparison).
- **Condition 2 of STRICT is a hoisting rule for reads (my inference).** A read may leave a loop only if the definition reaching it comes from outside the loop. For a read of `$a[0]`, "the definition" is the memory version it names, so it can be hoisted only if the loop header's memory Phi is trivial, that is, the loop writes nothing.
- **Does not apply:** landing pads, the four motion algorithms, the aliasing dictionary. A sea-of-nodes compiler gets loop-invariant motion by scheduling floating nodes into the right block (my inference). The safety discussion is still a useful reminder: Perl operations that can `die` must not be moved to where they would not have run.

## Limits and later work

The paper's own list (section 5): the motion algorithms depend heavily on COMMON, which is heuristic; a moved statement must receive the *same* value on every iteration, so code that is redundant only after the first iteration is missed (Figure 11); results depend on which topological order is chosen; NONSTRICT cannot reopen a placement decision. Join birthpoints are placed at every loop header for every variable defined in the loop, needed or not, and the general-graph case is delegated to Reif and Tarjan. Rosen, Wegman and Zadeck (1988) take the renaming from this paper ("essentially from [8], where the formulation looks different because explicit phi functions are not used"), add the phi notation and the name SSA, and reuse its landing pads. Cytron et al. (1991) describe such precursors as hard to work with "without explicit phi-functions" and give the general placement algorithm. Aycock and Horspool (2000) describe this paper as using "a heuristic placement policy based on the interval structure".
