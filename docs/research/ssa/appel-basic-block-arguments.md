# SSA is Functional Programming

**Authors, venue, year.** Andrew W. Appel (Princeton University). A four-page column in a "Functional Programming" series edited by Philip Wadler. The extracted text shows the column header and editor but no journal name or date; from background knowledge it is ACM SIGPLAN Notices, April 1998 (the reference list cites Appel's 1998 textbooks as new, which fits). **Source:** https://bernsteinbear.com/assets/img/appel-basic-block-arguments.pdf

*Extraction note: the prose is clean. The control-flow diagrams and the "crude SSA" figure are scrambled, so the worked example below is reconstructed from the code listings, which survived.*

## In one paragraph

A short, informal essay with one message: an SSA program and a functional program made of nested local functions are the same thing in different notation. Every basic block is a function. Every phi function is a formal parameter of that function. Every jump to the block is a call that supplies the actual arguments. And the well-known algorithm for placing the minimum number of phis is, seen from the other side, the algorithm for deciding how to nest those functions so that they pass as few arguments as possible. This is the idea behind the "basic block arguments" style used in several modern compilers (the term is the reading list's and my gloss; Appel does not use it).

## Key ideas

**Why SSA exists.** Analyses want to go from a definition to its uses and back. With ordinary variables, N definitions and M uses of one name can need N times M links. SSA gives each definition its own name, so each use links to exactly one definition. It also gets "the right number of names": a variable `i` reused for two unrelated loops becomes two variables.

**The crude version.** Split every variable at every block boundary and put a phi for every variable in every block. Obviously correct, and wasteful. ("Yuck!")

**Read as functions.** In the crude version every block is a function taking *all* variables as parameters, and every jump is a call passing all of them. Compare:

```
j2 = phi(j7, j1)                 # in block 2
function f2(..., j2, ...)        # same thing
    called as f2(..., j7, ...) and f2(..., j1, ...)
```

"The left-hand side of the phi assignment is the formal parameter of the corresponding function; and each right-hand side argument of the phi assignment is the actual parameter of some call."

**Worked example** (the paper's):

```
i = 1; j = 1; k = 0
while k < 100:
    if j < 20: j = i; k = k + 1
    else:      j = k; k = k + 2
return j
```

Minimal SSA needs phis only for `j` and `k`, at the loop header and at the join after the `if`. `i` is never reassigned and needs none. The functional form (lightly tidied from the paper):

```
let i1 = 1, j1 = 1, k1 = 0
in  function f2(j2, k2) =
        if k2 < 100
        then function f7(j4, k4) = f2(j4, k4)
             in if j2 < 20
                then f7(i1, k2 + 1)
                else f7(k2, k2 + 2)
        else return j2
    in f2(j1, k1)
```

`f2` is the loop header and its parameters `j2`, `k2` are the header's phis. `f7` is the join block. `i1` is not a parameter of anything: the inner functions simply see it, because they are nested inside its scope. "Wherever the functional form refers to a non-local variable, the SSA form has avoided the need for a phi."

**Scope is dominance.** Block A *dominates* block B if every path from the start to B goes through A. SSA requires that a variable's definition dominates every use. Appel points out this is "often unstated" yet is "part of SSA's semantics". In the functional form it is not a side condition at all: it is the nesting. A function can see a variable exactly when it sits inside that variable's scope.

## Construction / algorithm

No new algorithm. The column recaps the standard one in a few paragraphs:

- The *dominance frontier* of node `a` is the border of the region `a` dominates: node `c` is in it when there is an edge from a node dominated by `a` to `c`, and `a` does not strictly dominate `c`.
- Rule: "Whenever node n contains a definition of some variable, then any node in the dominance frontier of n needs a phi-function" for it (and, since phis are definitions, repeat).
- Inputs: the CFG and its dominator tree. For the details Appel sends readers to textbooks (his own *Modern Compiler Implementation*, chapter 19) and to Cytron et al.

The essay's point is the reinterpretation: this algorithm "is automatically converting a Fortran or C procedure into a well-structured functional program with nested scope".

## Memory, arrays, aliasing

One sentence, and it is a disclaimer: "I've only shown what to do with the scalar variables. Arrays are handled in high-powered (parallelizing) compilers using sophisticated dependence analysis techniques, which is another way of extracting the functional program hiding inside the imperative one." Nothing on pointers, aliasing or heap memory.

## Relevance to chalk / B::SoN

- **Adopt as the explanation of Phi.** In Click-style sea of nodes, a Region node merges control and its Phi nodes merge values. In Appel's terms the Region is a function, each Phi is a parameter, and each control input is a call site. So a Phi must have exactly one data input per control input of its Region, matched by position. That holds for memory Phis too (my application; the paper does not discuss sea-of-nodes).
- **Memory as a parameter (my inference).** Chalk's "memory is an SSA value" design is, in this picture, a hidden extra parameter threaded through every block-function, like a state argument in functional code. A write is a function from old memory to new memory. If a write does not hand its result on to whatever comes next, the functional program visibly drops the new state on the floor. That is the "write floats off the chain" bug stated as a functional-programming error: a computed value that nobody uses.
- **Dominance as the scoping rule for floating nodes.** Sea-of-nodes lets most nodes float, to be placed later. Appel's emphasis that "definition dominates use" is part of SSA's meaning is the condition a later placement must respect: a node may only be placed where all its inputs are "in scope" (my inference).
- **Warning by omission.** The essay stops at scalars. It gives no support for treating Perl arrays or hashes as SSA values. For that, see Cytron et al. section 3.1.
- **Not applicable:** chalk does not need to produce a functional program. T2 targets LLVM IR, which uses phi instructions directly.

## Limits and later work

This is an expository column, not a research result. Appel credits Kelsey (1995) for the precise correspondence and algorithms in both directions, Wegman, Zadeck, Alpern and Rosen for SSA, and Cytron et al. for the dominance-frontier construction, and he thanks Kenneth Zadeck, who "told me all along that SSA is a functional program". Aycock and Horspool (2000) take the "really crude approach" quoted from this column as the starting point of their own construction algorithm.
