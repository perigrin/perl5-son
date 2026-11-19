# FIRM - A Graph-Based Intermediate Representation ("the libFIRM paper")

**Authors, venue, year.** Matthias Braun, Sebastian Buchwald, Andreas Zwinkau (Karlsruhe Institute of Technology). Workshop on Intermediate Representations (WIR), Chamonix, 2011.  **Source:** https://bernsteinbear.com/assets/img/firm-ssa.pdf

*What I read and how: all 8 pages from the extracted text (clean), including the proofs in Section 3.3, the evaluation paragraph, related work, and the node table (Table 1) on the last page. Figures 1-4 are graph drawings; I reconstructed them from the node labels in the text and the surrounding prose.*

## In one paragraph

FIRM is a production-quality sea-of-nodes IR in the Click tradition, used by the libFIRM C compiler library. The paper does two things. First it describes the representation: a graph where each operation is a node, each edge points at the operation whose result is needed, multi-result nodes are unpacked by `Proj` nodes, and **memory is an explicit SSA value** threaded through `Load`, `Store`, `Call` and friends, with a `Sync` node to rejoin memory operations that were allowed to run independently. Second, it gives an SSA-construction algorithm that needs no dominator tree, works while the control-flow graph is still being built, and is proved to give pruned SSA always and minimal SSA for reducible programs. (This algorithm is the direct ancestor of the better-known Braun et al. 2013 paper.)

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Three kinds of optimisation.** *Explicit*: a separate pass. *Implicit*: done by the node constructor the moment a node is made (folding `2*3` to `6`). *Inherent*: there is nothing to do because the IR cannot even express the waste. The design goal is to make as much as possible inherent. Copy propagation is inherent (there is no copy node; a user simply points at the original value). Dead code elimination is inherent (a node nobody points at is unreachable from `End` and is never seen).

**The graph points backwards.** Edges are dependencies ("I need that"), not flow ("then go there"). A block's inputs are the jumps that reach it; the paper calls this a "reversed CFG".

**Blocks are nodes, and nodes name their block.** Unlike the purest reading of Click, every FIRM node's signature starts with a block input (`B`). Inside a block there is no list order, only the partial order the edges impose; a total order is chosen in the backend. (So FIRM floats *within* a block; moving between blocks is a transformation.)

**Proj.** A node with several results produces a tuple; `Proj` picks one out. `Start` yields a tuple of initial control, initial memory, two pointers and the argument tuple (signature `B -> X x M x P x P x T`). `Cond` (the branch) yields (false-control, true-control).

**Types on edges.** Edge kinds are explicit: `X` control, `M` memory, `P` pointer, `b` boolean, `T` tuple, plus numeric widths. An edge connects an output and an input of the same kind.

Worked example 1 (Figure 1): `int abs(int x) { if (x < 0) x = -x; return x; }`

```
Start -> Proj M (mem0), Proj X (ctl), Proj T (args) -> Proj Arg0 (x)
Cmp(x, Const 0) "less" -> Cond -> Proj X true, Proj X false
then-block (pred: Proj X true):   Minus(x), Jmp
join-block (preds: Jmp, Proj X false):  Phi(Minus(x), x)
Return(mem0, Phi)                 # Return consumes memory even though nothing wrote
```

Worked example 2 (Figure 2): `swap(int *x, int *y)`

```
mem0 = Proj M (Start)
L1 = Load(x, mem0) -> Proj res (t),  Proj M (m1)
L2 = Load(y, mem0) -> Proj res (v),  Proj M (m2)     # both loads read mem0: independent
m3 = Sync(m1, m2)                                    # barrier: wait for both
m4 = Proj M (Store(m3, x, v))
m5 = Proj M (Store(m4, y, t))
Return(m5)
```

## Construction / algorithm (steps, complexity, inputs it needs)

**Needs:** source statements in program order and the ability to add blocks and edges as you go. No dominator tree, no prior non-SSA IR. The paper credits the idea to "a little-known construction algorithm by Click".

Number the variables. Each block has an array: variable number to "node holding its latest value in this block".

1. `writeVariable(block, var, node)`: record it.
2. `readVariable(block, var)`: if the block has an entry, return it. Otherwise:
   - no predecessors (start block): the variable is used uninitialised; return an `Unknown` node;
   - block is *mature* and has exactly one predecessor: ask the predecessor;
   - otherwise create a Phi, **record it as the block's definition first** (this is what stops infinite recursion round a loop), then, if the block is mature, fill in its inputs by asking each predecessor.
3. A block is **immature** until every predecessor has been added. Phis created in an immature block are left empty. `matureBlock(block)` fills them in and marks the block mature. For a `while`, the header is matured only after the body's back-jump has been added.
4. **Remove unnecessary Phis.** When a Phi's inputs are all the same value `s` (ignoring references to itself), replace the Phi by `s`, then re-check any Phis that used it.

**Building from a syntax tree (Algorithm 2, Figure 4).** `if (C) S1 else S2`: create true, false and after blocks; emit the condition; mature true and false at once (their only predecessor is known); build each arm, add its jump to the after block; then mature the after block. `while (C) S`: jump into a new header block; emit the condition there; mature the body block; build the body; add the back-jump to the header; *only now* mature the header, then the after block.

**The paper's own trace (Section 3.1, Figure 3).** For a `do { if (...) {...} else {...} } while (...); return x;` that never assigns `x`, reading `x` at the `return` first yields `v0 = phi(v1, v1)` at the if-join and `v1 = phi(v2, v0)` at the loop head (`v2` is the parameter). The removal rule replaces `v0` by `v1`, making `v1 = phi(v2, v1)`, which is in turn replaced by `v2`: no Phis remain.

**Quality (Section 3.3) and the proof idea.**

- Too many Phis cost more than space: they "obscure information available to optimizations", because values that are really the same look different.
- *Pruned* (every Phi has a user): immediate, since a Phi is only ever created because a read or another Phi asked for it.
- *Minimal* in Cytron's sense: a Phi for `v` is *necessary* in block Z only if two paths that start at different blocks assigning `v` first meet at Z. The proof for reducible graphs (every cycle has one block that dominates the rest) goes by contradiction. The *SSA property* says a path from a definition to its use crosses no other definition of the same variable. Lemma 1: two distinct operands of a Phi cannot both come from blocks dominating the Phi's block. Lemma 2: an unnecessary Phi that the simple rule missed must have another unnecessary Phi as an operand, in a block that does not dominate it. Following that operand repeatedly must eventually go round a cycle of Phis, hence a cycle of blocks; in a reducible graph that cycle has a dominating entry block containing one of the Phis, contradicting Lemma 2. So nothing unnecessary survives (Theorem 1).
- *Less than minimal*: because copies are propagated on the fly, `x = y; if (...) { y = x }; use(y)` gets no Phi at all, where Cytron's algorithm would place one.
- The authors' intuition: "For goto-free programs we do not produce extraneous Phi-functions", which they say covers Java, JavaScript and Python.

**Complexity:** with B blocks, E edges, V variables: at most O(B·V) Phis and O(E·V) Phi inputs; O(E·V) time without Phi removal, O(B·V·E) with it.

**Evaluation (one paragraph, Section 3.3.5).** SSA construction for all C programs of SPEC CINT2000 took 1308 ms on a 2.6 GHz Core 2 Duo, "more than 1200 graph-nodes per millisecond". No comparison with another algorithm is given here.

**On-the-fly optimisations during construction (Section 2.3).** Implicit, done by node constructors with local knowledge only: arithmetic simplification (`x - x` gives 0), common subexpression elimination (asking for `Const 1` returns the existing one), constant folding. Inherent: copy propagation and dead code elimination. Because they are local they are conservative; optimistic versions (e.g. unreachable-code elimination that needs to assume a branch dead before it can prove it) are separate passes.

**After construction: the backend (Section 4.2).** libFIRM keeps the graph, and SSA, all the way down: *instruction selection* by graph rewriting; *scheduling*, described as inserting extra dependency edges until each block's nodes are totally ordered; *register allocation* on SSA form, where spilling is separated from assignment and no interference graph is built.

## Memory, arrays, aliasing (what it says, or "not addressed")

This is the fullest treatment among the three central papers.

- Scalar locals whose address is never taken become SSA values. A variable whose aliasing is unknown "is simply not represented in SSA-form": every access is an explicit `Load` or `Store`.
- Ordering of those is modelled by "a new SSA-value called memory which represents aliased variables and heap data. Load- and Store-nodes consume a memory value and produce a new one."
- **Note the difference from Click:** in FIRM a `Load` *also* returns a memory value (signature `Load: B x P x M -> Num x M`; `Store: B x M x P x Num -> M`). A strict chain therefore orders loads too.
- **Relaxing the chain with `Sync`.** If operations are known not to interfere (alias information, or they only read), give them all the *same* memory input and combine their memory outputs in a `Sync` node (`M0 x ... x Mn -> M`), "which forms a barrier for subsequent potentially aliasing operations". Thus "alias analysis results can be directly encoded in the graph structure".
- Other memory users in the node table: `Call` (takes and returns `M`), `Alloc`, `Free`, `Sel` (field select), `Return` (consumes `M`), and `NoMem` ("empty subset of memory").
- The authors deliberately do **not** adopt virtual-definition schemes that put aliased variables into SSA (HSSA-style). Their argument: where aliasing is real there is little to optimise; where it is not, Load/Store pairs on the same address get promoted to SSA values by scalar replacement anyway.
- **The full node table (Table 1)** lists about 40 node kinds. Worth noting for chalk: `Div` and `Mod` appear with a purely numeric signature (block and two numbers in, a number out), i.e. in this paper's table they carry neither memory nor a control result, so the paper gives no model for a faulting division; `Bad` is "value of unreachable calculation" and `Unknown` is "undefined value"; `Mux` selects one of two values by a boolean without control flow.
- Arrays are not addressed specifically. The node table shows `Phi` over numeric types only; that Phi also merges memory at joins is my reading of "memory is an SSA value", not a statement in the text.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **Explicit Store/Load vs effectful nodes as memory versions.** FIRM does both at once: `Load`/`Store` are explicit, and *any* effectful node (`Call`, `Alloc`) simply has an `M` input and an `M` projection. So the choice is not either/or; the rule is "anything that touches memory takes M and returns M via Proj". That is a rule a verifier can check per node class.
- **One chain vs alias-class slices.** `Sync` is the alternative to permanent slices: keep one memory value, fork it where independence is proven, and rejoin. Compared with Click's "one STORE per variable" it needs no global partition up front, which suits Perl where independence is usually local knowledge (a fresh lexical `my @a` that has not escaped). This lines up with deferring array SSA to an escape-analysis pass.
- **Should a Load produce a new memory version?** FIRM says yes; Click says no. FIRM's form means the chain alone fixes read-before-write ordering (no hidden anti-dependence for T2 to respect), at the cost of needing `Sync` to recover load reordering. For a first correct implementation lowering to LLVM, FIRM's stricter form is the safer default. (Inference.)
- **Structural invariant.** `Return` takes `M`. Combined with inherent dead-code elimination, a write whose memory output does not lead to `Return`/`End` is not merely misplaced, it is *deleted*. That is the "floats off the chain" bug stated in FIRM terms, and the check is: walk back from `End`; every Store-like node must be reached via `M` edges.
- **Construction algorithm: adopt.** B::SoN walks perl's op tree in execution order with structured control flow, exactly the setting here. Treat "current memory" (and "current I/O", "current control") as extra numbered variables alongside the lexicals: `Store` does `writeVariable(mem, new)`, a read does `readVariable(mem)`, and memory Phis appear automatically at joins and loop headers with no special code. (Inference; the paper does not spell this out.)
- **Declaration vs use.** The variables array is indexed by declared variable, and an undeclared read in the start block is an explicit `Unknown`. That is "type by declaration" in structure: a variable's facts live on its defining node.
- **I/O and die ordering:** not separated in FIRM; calls carry everything through `M`. Chalk's separate I/O chain follows Click, not FIRM.

## Limits and later work

The paper compares itself only with Cytron et al. (which does give minimal SSA for irregular control flow, at the price of needing the complete graph and dominator tree) and notes that richer graph IRs (program dependence graph, gated SSA, VSDG) enable stronger optimisation "but generating good code from these appears to be very challenging"; the authors had seen none handle SPEC-sized programs. Phi nodes break the "everything is in the edges" rule: all Phis of a block must be evaluated simultaneously, which no edge expresses. Minimality is only guaranteed for reducible control flow (Perl `goto` and `redo`/`last LABEL` can break that). The successor paper, Braun et al., "Simple and Efficient Construction of Static Single Assignment Form" (CC 2013), restates the algorithm with "sealed" blocks, handles irreducible flow, and measures it against LLVM.
