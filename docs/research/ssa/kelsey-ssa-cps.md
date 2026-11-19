# A Correspondence between Continuation Passing Style and Static Single Assignment Form

**Authors, venue, year.** Richard A. Kelsey (NEC Research Institute). IR '95 (ACM SIGPLAN Workshop on Intermediate Representations), San Francisco, January 1995. **Source:** https://bernsteinbear.com/assets/img/kelsey-ssa-cps.pdf

*Extraction note: scanned PDF. The prose is readable. The formal translation tables (Figures 1, 3 and 4) are badly garbled, so I describe the translations from the surrounding prose.*

## In one paragraph

Compilers for functional languages (Scheme, ML) had long used an intermediate form called continuation-passing style (CPS). Compilers for imperative languages (Fortran, C) had started using SSA. Kelsey shows these are the same thing written two ways: there is a simple, purely syntactic translation from (suitably annotated) CPS to SSA and one back. A phi function is the parameter of a local function, and a jump to a block is a call to it. The paper also explains exactly where the two forms differ, and what happens to a program that mutates variables.

## Key ideas

**CPS, briefly.** In *continuation-passing style* no function ever returns. Each function takes an extra argument, the *continuation*: a function representing "the rest of the computation", which it calls with its result. Every intermediate value is bound to a name exactly once, and names are visible only inside the function that binds them (lexical scope).

**The shared property.** "In CPS there is exactly one binding form for every variable and variable uses are lexically scoped. In SSA there is exactly one assignment statement for every variable, and that statement dominates all uses." (A definition *dominates* a use if every path from the start of the program to the use passes through the definition.) Nesting in the text and dominance in the graph express the same restriction.

**Three kinds of lambda.** Kelsey's CPS conversion tags each function with how it is used:

- `proc`: a real procedure from the source; needs a full call.
- `cont`: the return point of a call.
- `jump`: a continuation called only from inside the current procedure, created where the arms of an `if` rejoin and for loop bodies. It can be compiled as a `goto`.

**The correspondence.**

| CPS | SSA |
|---|---|
| `let` binding, parameter of a `cont` | assignment |
| `jump` lambda bound by `letrec` | labelled block |
| parameters of the `jump` lambda | phi functions at the top of the block |
| call to a `jump` lambda | `goto`; its arguments are the phi operands |
| call to the procedure's own continuation | `return` |

**Worked example** (the paper's running example simplified): count zeros of `f(0) .. f(limit-1)`.

SSA:

```
l:  i = phi(0, i+1);  c = phi(0, c')
    if i == limit: return c
    x = f(i)
    if x == 0: goto j (first way in) else goto j (second way in)
j:  c' = phi(c+1, c);  goto l
```

CPS, as pseudo-code:

```
function l(i, c):
    if i == limit: return c
    x = f(i)
    function j(c'):  l(i+1, c')
    if x == 0: j(c+1) else j(c)
l(0, 0)
```

Block `l` with two phis is function `l` with two parameters. The two `goto l` sites are the two calls `l(0, 0)` and `l(i+1, c')`. Lined up, their arguments are the phi operand lists: `(0, i+1)` and `(0, c')`.

## Construction / algorithm

- **CPS to SSA** (function G): a one-pass syntactic walk. Bindings become assignments. Each `jump` lambda is lifted out to become a labelled block, and the arguments at its call sites are collected into phi functions. No flow analysis is needed, because the source was functional and already carried the information.
- **SSA to CPS** (function H): the reverse, with one real decision: where to put each block's function so that every variable it mentions is in scope. Answer: bind it immediately inside its *immediate dominator* (its closest dominator). So this direction needs the **dominator tree** of the SSA program. A short proof shows all variables end up properly scoped.
- **Loop merging** (section 8): functional programs write loops as recursive procedures, which hides them from SSA-style analysis. If a set of procedures is always called with the same continuation, substitute it in; the procedures become `jump` lambdas inside one big procedure, and the loop becomes an ordinary SSA loop with phis.

No complexity figures are given; the translations are linear walks.

## Memory, arrays, aliasing

Arrays and aliasing are not addressed, but section 7 says something that matters for memory. The source language has no assignment. For a program that uses `set!` (Scheme's assignment to an existing variable), translation "would have required adding explicit cells to hold the values of all variables that were the targets of set! expressions". The result: the join points "would take no arguments and there would be no phi-functions in the corresponding SSA program, only a lot of stores and fetches. Transforming such a program into a more useful form would require doing some flow-analysis, similar to that done in translating imperative programs to SSA."

In plain terms: the free ride only works for variables that are never mutated. A mutated variable either stays a memory cell with loads and stores, or the compiler must do real SSA construction to turn it back into values.

The paper also assumes that lexical scoping "has been implemented by introducing explicit environments", meaning closures have already been turned into data structures that hold their captured variables.

## Relevance to chalk / B::SoN

- **A mental model, not an algorithm to adopt.** A Region with Phis is a local function with parameters; each incoming control edge is a call site supplying arguments. This gives a quick sanity check on any Phi: it has exactly one input per incoming control edge, in the same order (my application of the paper's table to sea-of-nodes).
- **Section 7 describes chalk's scalar/memory split.** Perl lexicals are mutable, so they are in the `set!` case. Chalk's design does the flow analysis for plain lexical scalars (they become SSA values with Phis) and leaves containers as "stores and fetches" against memory. The paper confirms these are the only two options, and that a cell-based variable produces no Phi of its own. Under chalk's design the merging happens in the memory Phi instead (that last step is my inference).
- **Closure-captured scalars belong in memory.** The "explicit environments" assumption is the functional-language statement of the same rule: a variable shared with a closure lives in an environment record, a memory object, not in an SSA name. This supports chalk's placement of captured scalars in memory.
- **Where the correspondence breaks.** Continuations used for non-local exits (C's `longjmp`, Scheme's call/cc) fit neither `cont` nor `jump` and have "no direct way" into SSA. Perl's `die`/`eval` and `goto &sub` are of this kind (my comparison), so they need explicit control edges, not anything derived from this correspondence.
- **Not applicable:** the CPS conversion itself and the loop-merging transformation. Perl loops are already loops.

## Limits and later work

The correspondence holds only within one procedure and only for continuations used in a last-in, first-out way. Kelsey notes that Appel and O'Donnell had observed the phi/parameter similarity earlier; his contribution is that it is exact and goes both ways. Appel's 1998 column "SSA is Functional Programming" retells the result for a general audience and connects optimal phi placement to choosing the best nesting of functions.
