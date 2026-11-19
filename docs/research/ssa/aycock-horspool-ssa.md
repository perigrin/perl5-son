# Simple Generation of Static Single-Assignment Form

**Authors, venue, year.** John Aycock and Nigel Horspool (Department of Computer Science, University of Victoria, Canada). Compiler Construction, CC/ETAPS 2000, Springer LNCS 1781, pages 110-125, 2000. **Source:** https://bernsteinbear.com/assets/img/aycock-horspool-ssa.pdf

*Extraction note: clean text. Some figures are flattened but legible. I read through section 6 (future work); the last few lines and the references I did not read.*

## In one paragraph

Instead of working out where phi functions are needed, put one *everywhere* and then delete the ones that turn out to be pointless. That is the whole algorithm: a "really crude" phase that gives every variable a phi in every block, followed by a minimisation phase that applies two tiny deletion rules until nothing changes. The paper proves the result is always correct, and for *reducible* control flow (loops with a single entry point) exactly as small as the Cytron et al. answer. It needs no dominator tree and no dominance frontiers, and in the authors' measurements it runs about as fast as Cytron's algorithm.

## Key ideas

**Terms.** A *phi function* `V3 = phi(V1, V2)` sits at the top of a block and yields V1 or V2 depending on which predecessor control came from. Block A *dominates* B if every path from the start to B goes through A. The *dominance frontier* of A is where A's dominance ends, which is where the standard algorithm places phis.

**Starting point.** Appel's column describes "a really crude approach": split every variable at every block boundary and put phis for every variable in every block. The authors ask whether you can get to the minimal answer by deleting from there.

**The two rules.**

1. Delete `Vi = phi(Vi, Vi, ..., Vi)`. It says "V is itself".
2. Delete `Vi = phi(...)` when every operand is either `Vi` itself or one other name `Vj`, and replace `Vi` by `Vj` everywhere. The phi only ever passes `Vj` along, so `Vi` is just another name for `Vj`.

Repeat until neither applies.

**Worked example.**

```perl
my $i = 0;
while ($i < 10) { $i = $i + 1 }
print $i;
```

After the crude phase (blocks: entry, loop header, body, exit):

```
entry:   i1 = 0
header:  i2 = phi(i1, i4)      # from entry, from body
body:    i3 = phi(i2);  i4 = i3 + 1
exit:    i5 = phi(i2);  print i5
```

Rule 2 removes `i3 = phi(i2)` (replace i3 by i2) and `i5 = phi(i2)` (replace i5 by i2):

```
header:  i2 = phi(i1, i4)
body:    i4 = i2 + 1
exit:    print i2
```

`i2 = phi(i1, i4)` has two different operands, neither of them itself, so it stays. That is the one phi the standard algorithm would place.

Now give the same program a second variable `$j` that the loop never assigns. Its header phi is `j2 = phi(j1, j2)` once the body's phi is gone. Its operands are itself and one other name, so rule 2 deletes it and `j1` is used throughout. Variables untouched by a loop lose all their phis.

## Construction / algorithm

1. **RC phase:** insert a phi for each variable in each block.
2. **Minimisation phase:** apply rules 1 and 2 to a fixed point.
3. **Renaming** as in any other SSA construction.

Inputs: the CFG and each block's predecessor list. Nothing else.

Three refinements the paper recommends:

- *One-pass RC phase.* Name the version of V leaving block Bi "Vi". Then a block's phi operands are known from its predecessors' block numbers alone, with no need to process predecessors first or patch back edges later.
- *Mapping table.* Do not literally rewrite every `Vi` to `Vj`. Keep a table mapping `Vi` to `Vj` and look names up through it. This is the classic union-find (disjoint-set) structure.
- *Single-predecessor blocks.* Such a block cannot be a join, so skip the phi and just prime the table.

**Correctness** (any CFG): the crude phase contains every needed phi, and the two rules only remove phis that no minimal solution could contain.

**Minimality** (reducible CFGs): the proof views each variable's phis as a graph of "which name feeds which", shows that the two rules are the classic T1/T2 graph reductions (remove a self-loop; merge a node into its unique predecessor), and that what survives is exactly the iterated dominance frontier of the real definitions.

**Complexity:** not determined. The authors list it as future work and argue it hardly matters. Timings on about 26,000 lines of Modula-2 show it competitive with Cytron's algorithm, and SSA construction as a negligible share of total compile time.

A side benefit they note: when the algorithm finishes it already knows each phi's operands, which Cytron's algorithm only learns during renaming.

## Memory, arrays, aliasing

Not addressed. Variables are scalars.

## Relevance to chalk / B::SoN

- **Adopt the two rules as Phi peepholes (my inference).** In a sea-of-nodes graph, "replace `Vi` by `Vj` everywhere" is ordinary node replacement, and Click-style builders already simplify a Phi whose inputs are all the same. The paper supplies the proof that doing *only* this, starting from "Phi for everything at every Region", yields minimal SSA for reducible graphs. So B::SoN may over-create Phis freely, including one memory Phi at every Region, and rely on these rules to clean up.
- **Rule 2's self-reference case is the loop case.** A loop header Phi of the form `phi(entry_value, itself)` means "the loop does not change this". For the memory Phi, that says "this loop writes nothing", which is useful for hoisting reads out of the loop. And the converse is a symptom: if a loop contains a write to `$a[0]` yet the header's memory Phi collapses, the write was not on the chain. This turns the known bug class into something a test can detect (my inference).
- **A cross-check for B::SoN's Phi placement.** Because the method needs only predecessor lists, it is cheap to implement as a second, independent construction and compare Phi sets in tests.
- **Irreducible control flow.** Perl's `goto LABEL` into a loop body could produce it. This algorithm stays correct there but may leave extra Phis. Harmless, but do not write tests that assert minimality for such code.
- **Does not apply:** the method does not produce *pruned* SSA. Phis for values that are dead afterwards remain unless something else removes them. In sea of nodes an unused Phi has no users and is removed as dead code anyway (my inference).

## Limits and later work

Minimal only for reducible graphs; complexity unproven; pruned SSA left as future work. The paper notes that Rosen, Wegman and Zadeck already looked for the same two patterns, but only as a cleanup after other optimisations. Nguyen and Scholz (2007) summarise this paper as placing "a minimal number of phi-function nodes for reducible flowgraphs but not for irreducible graphs". From background knowledge, not from these texts: Braun et al. (2013), also on the reading list, use the same trivial-phi removal inside an on-the-fly construction and handle the irreducible case with an extra step.
