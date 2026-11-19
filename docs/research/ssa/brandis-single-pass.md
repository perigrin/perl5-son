# Single-Pass Generation of Static Single-Assignment Form for Structured Languages

**Authors, venue, year.** Marc M. Brandis and Hanspeter Mössenböck (ETH Zürich). ACM Transactions on Programming Languages and Systems, vol. 16 no. 6, November 1994, pages 1684-1698. **Source:** https://bernsteinbear.com/assets/img/brandis-single-pass.pdf

*Extraction note: scanned PDF with wide, irregular spacing and some misread characters ("phi" appears as `@`, `~` or `+`). The prose and both pseudocode procedures are readable; the figures are not.*

## In one paragraph

If a language has only structured control flow (`if`, `while`, `repeat`, `for`, `case`, and no `goto`), the compiler already knows where every join point is the moment it starts parsing a statement. So it can build SSA while it parses, in one pass, without first building a control flow graph, a dominator tree, or dominance frontiers. The paper gives the method, shows that the dominator tree can also be built on the fly, extends both to disciplined exits (`LOOP`/`EXIT` and `RETURN`), and reports an implementation of about 250 lines in an Oberon compiler.

## Key ideas

**Current value.** Each variable's symbol-table entry holds its *current value*: the SSA name a use would get right now. An assignment `v = ...` creates a new name `v_i` and makes it current. A use reads the current value.

**Join nodes are known in advance.** An `if` has one join node, after its branches. A `while` has one, its loop header, where the entry and the back edge meet. A `repeat` loop's join node is also its header. The join node of the innermost statement being compiled is the *current join node*.

**Every assignment feeds a phi immediately.** An assignment inside a branch will make that variable differ at the join. So at the moment of the assignment, the compiler creates (or updates) a phi for that variable in the current join node and sets the operand for the current branch.

**Worked example.**

```perl
if ($c) { $a = 1; $b = $a + 1 } else { $a = $a + 1 }
```

Starting from `a0`, `b0`:

- Parsing `$a = 1` creates `a1` and inserts `a2 = phi(a1, a0)` in the join node. The old value `a0` is also stored in the phi as the *backup value*.
- `$b = $a + 1` creates `b1 = a1 + 1` and `b2 = phi(b1, b0)`.
- At `else`, current values are reset from the backups: `a` is `a0` again, `b` is `b0`.
- `$a = $a + 1` creates `a3 = a0 + 1` and updates the existing phi to `a2 = phi(a1, a3)`.
- At the end of the `if`, the phis are *committed*: `a2` and `b2` become current, and each commit counts as an assignment for the next enclosing join node.

`b` was not assigned in the `else` branch, so its phi operand there stays `b0`, the value at the start of the branch.

**Loops.** A phi placed in a `while` header changes the variable's value for the *whole* loop, including uses already compiled. So when a phi is first inserted in a loop header, all earlier mentions of the old value inside the loop are renamed to the phi's name, by walking the old value's use list. (Example: in `a = 1; while cond { b = a + 1; a = a * 2 }`, `b1 = a1 + 1` is rewritten to `b1 = a3 + 1` once `a3 = phi(a1, a2)` appears.)

## Construction / algorithm

Two procedures.

- `InsertPhi(b, i, v_new, v_old)`: if join node `b` has no phi for `v`, insert `v_j = phi(v_old, ..., v_old)` with backup `v_old`; if `b` is a loop header, rename mentions of `v_old` in the loop to `v_j`. Then set operand `i` to `v_new`.
- `CommitPhi(b)`: for each phi in `b`, make its result the current value and call `InsertPhi` on the enclosing join node. Exception: after a `repeat` loop the current value is the phi's *second operand* (the value coming around the back edge), because control leaves from the bottom of the loop, not through the header.

Inputs: only the source text and a symbol table. No CFG, no dominator tree.

**Dominator tree on the fly.** For structured statements the immediate dominator of each new block is known when the block is created (the paper's Figure 12 gives the patterns).

**Unstructured exits.** `EXIT` and `RETURN` make a branch *dead*. Its operands are removed from the current join's phis, and the immediate dominator of a join becomes the closest common dominator of its live incoming branches. For the node after a `LOOP`, phis are found by walking the dominator tree from each `EXIT` back to the loop header. The authors say they "do not elaborate"; it is shown to be possible, not spelt out in full.

**Complexity.** Worst case O(r^3), the same as Cytron et al., since the size of SSA form does not depend on how it is built; linear in practice. They measured about 1.2 phis per original assignment.

## Memory, arrays, aliasing

Explicitly out of scope: "We do not deal here with alias problems caused by assignments to array elements, to parameters passed by reference, and to variables that are referenced via pointers. These problems can be dealt with in the same way as described by Cytron et al."

## Relevance to chalk / B::SoN

This is the construction paper that fits B::SoN's situation most closely: B::SoN also walks a tree-shaped program (perl's op tree) and wants SSA directly, with no separate CFG pass.

- **Adopt the bookkeeping.** A table from each declared lexical to its current SSA node; a phi created at the join the moment an assignment happens inside a branch; backup values restored between branches; commit at the end of the statement. Sea-of-nodes builders in Click's tradition keep a similar per-scope table of current definitions (my observation, not the paper's).
- **Treat memory as one more variable in that table (my inference).** If "current memory" is an entry like any other, then every write is an assignment to it. It gets a new version, and a memory Phi appears at the enclosing join through the same `InsertPhi` path as for `$x`. The known bug class has a precise description in these terms: a write that floated off the chain is an assignment that did not update the current-value entry. This suggests a check: after building any op that can write, assert that current memory changed.
- **Keying by declaration.** The scheme hangs the current value on the variable's symbol-table entry, that is, on the declaration (`my $x`, the pad entry), not on what a use looks like. That is the discipline B::SoN's typing-by-use bug is missing (my inference).
- **The loop rule is where errors hide.** Uses compiled before the loop-header phi existed must be patched. Miss that and the loop body reads the pre-loop value for ever. The same holds for memory: a read inside a loop, compiled before the first write in that loop, must be re-pointed to the header's memory Phi.
- **`repeat`, `EXIT`, `RETURN`** correspond to `do {} while`, `last`/`next` and `return`. The dead-branch treatment is what `last` needs. The paper does not cover `die`/`eval`, `redo`, or `goto`.
- **Does not apply:** arrays, references, by-reference parameters (`@_` aliasing). The paper sends you to Cytron section 3.1 for those.

## Limits and later work

Structured programs only, plus the sketched exits. Renaming uses inside a loop when a late phi appears costs a walk of the use list. The claim of being faster than Cytron et al. is stated as a belief still to be confirmed by measurement. Aycock and Horspool describe this method as needing "delicate placement of phi-functions" and note that the extension beyond structured code requires the dominator tree. From background knowledge rather than the papers summarised here: Braun et al. (2013), also on the reading list, generalise the "current definition per variable" idea to arbitrary control flow.
