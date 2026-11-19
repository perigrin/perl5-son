# One Representation to Rule Them All: Combining Analyses on SSA with On-Demand SSA Construction (Paul Biggar's algorithm sketch)

**Authors, venue, year.** Paul Biggar and David Gregg, Trinity College Dublin. FIT session at PLDI, Dublin, 16 June 2009 (a two-page "fun ideas" paper). Biggar's implementation lives in phc, his PHP compiler.  **Source:** https://bernsteinbear.com/assets/img/biggar-ssa.pdf

## In one paragraph

A deliberately light-hearted two-pager about a serious problem. In languages like PHP (and Perl) you cannot build good SSA without first knowing what may alias what, yet the best alias analyses want to *run on* SSA. The proposal: stop treating SSA construction as a pass that happens first. Instead make it one more client of the same engine that drives constant propagation, so that SSA form, alias information, constants and types are all discovered together, on demand. The paper sketches such an algorithm and is candid that it is "completely unproven, and barely tested, but it looks right".

## Key ideas (intuitive first, then the mechanism; one small worked example)

**The chicken-and-egg.** SSA (static single assignment: every variable has one definition) is what makes analyses cheap and precise. But an assignment through a reference might change *any* variable the reference could point at, so to place definitions correctly you need alias analysis first. That first analysis then cannot benefit from SSA. Iterating "SSA, alias analysis, SSA again..." is slow, and the paper says for PHP it is not even possible, because there is no safe-but-useful starting guess for what aliases what.

A Perl flavour of the problem (my example):

```perl
my $x = 1;
$$r = 2;        # if $r refers to $x, this is a new definition of $x
print $x;       # 1 or 2?
```

Whether `$$r = 2` counts as an assignment to `$x` decides how many versions of `$x` exist.

**SCCP as a general engine.** Sparse Conditional Constant Propagation (Wegman and Zadeck) "pretends to run" the program over abstract values. It keeps two to-do lists: control-flow edges not yet shown to be executable, and SSA edges (definition to use) whose source has changed. It never analyses code it has proved unreachable. The same engine already works for value ranges and types.

**The idea.** Let that engine build the SSA edges as it goes. When it meets a use, it looks up which definition reaches it; when it meets a definition, it creates a new version, schedules Phis, and re-queues the uses that might now see something different. Alias facts discovered along the way can add definitions, which simply queue more work.

## Construction / algorithm (steps, complexity, inputs it needs)

**Assumes:** dominance information (each block's immediate dominator and dominance frontier) is available; the program starts with unversioned variables and no Phis; Phis go first in a block.

Following the SCCP worklists, for each statement `s` in block `bb`:

1. **For each use `u` in `s`:** find its version by searching *upward through the dominator tree* from `bb` for a definition of `u`. If none is found use version zero. If `s` is a Phi, start the search in the predecessor matching that operand. If `u` already had a version, recompute it anyway: a new definition (a Phi, or an alias-induced one) may have been inserted in between.
2. **For each definition `d` in `s`:** add an unversioned Phi for `d` at each block in `bb`'s dominance frontier and queue it; give `d` a fresh version; then queue (a) all still-unversioned uses of `d`, and (b) the uses of the version of `d` that held just before this point, since this definition may now sit between an older definition and its use.

**Complexity:** "We haven't thought about complexity." The authors note the version search wants caching.

## Memory, arrays, aliasing (what it says, or "not addressed")

Aliasing is the whole motivation, but the mechanism is only gestured at. The paper refers to Hashed SSA (HSSA), which adds chi nodes ("this statement *may* define that variable") and mu nodes ("may use"), and says a definition may be inserted "due to the addition of a Phi node, or a chi node in HSSA form". Requirements 2 and 3 (merging alias results into construction, and running everything at once without error) are, in the authors' words, proved "by hand waving". Arrays are not addressed.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **It names chalk's design pressure exactly.** Perl has PHP's problem: references, `local`, `@_` aliasing, `foreach` aliasing, symbol-table access. The paper is evidence that "decide statically which variables are safely SSA values" is hard in such languages.
- **Chalk's current split is the conservative answer to this paper.** Only plain lexical scalars are SSA values; anything that can be reached another way (containers, elements, closure-captured and package scalars) stays in memory. That avoids needing alias analysis before construction. The cost is precision, to be bought back later by escape analysis. The risk to watch is on the boundary: a lexical scalar that has had a reference taken (`\$x`) or is captured by a closure must be classified as memory **from its declaration**, not from how a particular use looks. This is the "typing by use instead of declaration" bug seen from another angle. (Inference.)
- **For T1:** the paper's architectural point, that types, intervals, constants and reachability should be solved in one SCCP-style fixed point rather than in separate passes, applies directly to chalk's type and integer-interval analyses. It is the same argument Click's thesis makes.
- **Do not adopt the algorithm as written.** It needs dominance frontiers (which B::SoN's construction otherwise avoids), is unproven, and has no complexity bound.

## Limits and later work

The paper lists its own gaps: unknown generality, no complexity analysis, no treatment of minimal or pruned forms (pruned needs liveness, which "doesn't fit nicely into the SCCP framework"), exceptions not handled. Biggar's PhD thesis on phc (Trinity College Dublin, 2010; my addition) develops the PHP analysis in full. Lemerre's "SSA Translation Is an Abstract Interpretation" (POPL 2023) is a rigorous realisation of the same wish: SSA construction as one analysis among several, combined in a single pass.
