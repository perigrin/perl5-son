# Pizlo SSA Form ("Phi/Upsilon form") and "How I implement SSA form"

**Authors, venue, year.** Filip Pizlo. Two GitHub gists, 2025: "Pizlo SSA Form (short version)" and "How I implement SSA form". Folded in: the Bril documentation page "Static Single Assignment (SSA) Form (New!)" (Cornell CAPRA), which adopted the form.  **Source:** https://gist.github.com/pizlonator/79b0aa601912ff1a0eb1cb9253f5e98d and https://gist.github.com/pizlonator/cf1e72b8600b1437dda8153ea3fdb963 ; Bril: https://capra.cs.cornell.edu/bril/lang/ssa2.html

## In one paragraph

An opinionated practitioner's guide to building an SSA compiler (Pizlo designed several of JavaScriptCore's IRs). Its signature idea is to cut the Phi in two. A classic Phi sits at the top of a join block and lists one input per incoming edge, which ties the data-flow representation to the shape of the control-flow graph. In Pizlo's form the Phi takes no inputs at all; instead each predecessor contains an `Upsilon` instruction that says "send this value to that Phi". Blocks and edges then know nothing about SSA, so control-flow transformations need no Phi repair. The longer gist adds four more habits: every value is an instruction; blocks are plain arrays of instructions (insertions are batched, deletions become `Nop`s); there are no use lists (to replace a value, turn it into `Identity(other)` in place); and all side effects are described uniformly as reads and writes of "abstract heaps".

## Key ideas (intuitive first, then the mechanism; one small worked example)

**Phi/Upsilon.** Every Phi owns a hidden *shadow variable* (written `^X` for Phi `X`). `Upsilon(V, ^X)` stores `V` into the shadow variable. `X = Phi()` loads it. That is the entire semantics. The only way to read a shadow variable is its Phi, so shadow variables are "static single *use*"; Pizlo calls the whole thing SSA-SSU form.

```c
int x;
if (a) x = b + 1; else x = b * 2;
return x + 42;
```

```
root:   A = GetArgument(0);  B = GetArgument(1);  Branch(A, then, else)
then:   X1 = Add(B, 1);  Upsilon(X1, ^X);  Jump(return)
else:   X2 = Mul(B, 2);  Upsilon(X2, ^X);  Jump(return)
return: X = Phi();  R = Add(X, 42);  Return(R)
```

A Phi may appear anywhere in a block, even right after its own Upsilon. The `^X` in an Upsilon is a special field, not a data-flow argument.

**Bril's version.** Bril calls Upsilon `set` and Phi `get`: `set c a;` copies `a` into shadow variable `c`; `c: int = get;` reads it; at most one `get` per shadow variable per function. Bril adds `undef`, a value that may only be copied, never used, for paths where a variable has no definition.

**Instruction-value uniformity.** Constants, arguments and Phis are all instructions (`One = Const(1)`), so passes never special-case "operands that are not instructions".

**Uniform effects.** Each instruction reports which *abstract heaps* it reads and writes. Heaps form a tree with `World` at the root; two heaps interfere if they are the same or one is an ancestor of the other, so a heap can be stored as a pair of integers (pre-order and post-order number) and interference is a range-overlap test. An instruction with no effects can be moved, duplicated or deleted freely.

## Construction / algorithm (steps, complexity, inputs it needs)

The gists describe a representation, not a construction algorithm. The practical recipe (partly my reading): emit one Phi per variable at each join and an Upsilon at the end of each predecessor, then clean up. Cleanup is stated explicitly: "you can implement [Phi simplification] either by running Cytron or by running any other SSA converter. The simplest is just to fixpoint the rule that if you have a Phi that has Upsilons that only use the Phi or exactly one other value, then replace the Phi with that other value." Dead-code elimination should mark an Upsilon live only if its Phi is live. Finding "the Upsilons of this Phi" is a linear scan of the function, accepted because passes are linear anyway. A `validate` pass between passes checks the rules (for instance that each use is dominated by its definition).

## Memory, arrays, aliasing (what it says, or "not addressed")

Addressed through the effect system rather than through SSA. Memory is **not** an SSA value here: loads, stores and calls carry a list of abstract heaps they read or write, supplied by whoever generates the IR (a heap per field name, per points-to set, or a single `Memory` heap if nothing better is known). The suggested starting hierarchy is:

```
World
  Memory
  SSAState     (Upsilon writes it, Phi reads it)
  Control      (branches write it; anything that may trap reads it)
```

`Control` is how trap ordering is kept: a load that may fault *reads* Control, branches and "side-exiting" checks *write* it, so the load cannot be hoisted above a branch. Pizlo explicitly prefers this to "fake data flow edges (that just pass a 0-bit token value)", which he finds "annoying in practice".

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **It is the opposing school to chalk's design, and worth reading as such.** Chalk threads memory as an SSA value (Click). Pizlo keeps a scheduled control-flow graph and uses effect sets instead. His complaint about token edges is the cost chalk has chosen to pay; what chalk buys is that ordering is visible in the graph and nodes can float.
- **Adopt the vocabulary of abstract heaps for the alias-slice question.** A tree of heaps (`World` > `Memory` > `Arrays`, `Hashes`, `PackageVars`, `Captured` ...; siblings `IO`, `Control`) with integer-range interference is a cheap, precise way to *name* slices before committing to separate memory chains. A sea-of-nodes design can use it as the label on each memory edge. (Inference.)
- **`Control` as a separate heap** is the same conclusion as Click's separate control input: keep `die` ordering apart from memory. Likewise an `IO` heap matches chalk's separate I/O chain.
- **Every effectful node declares its effects.** A per-node-class "reads/writes" table is a natural place to hang chalk's invariant: any class that declares a Memory write must have a memory input and output. That turns the "write off the chain" bug into a table-driven check. (Inference.)
- **Does not apply:** arrays-of-instructions, InsertionSet and no-use-lists are advice for block-structured IRs in C++; a floating graph has no instruction order to insert into. T2 targets LLVM, which wants classic Phis.

## Limits and later work

No proofs, no measurements, no construction algorithm; the gists say so. Finding a Phi's inputs costs a scan. The effect system is a baseline, and passes may need sharper analyses. Bril's adoption (with interpreter and type-checker support, replacing its older `phi` extension) is the main independent uptake recorded in these sources.
