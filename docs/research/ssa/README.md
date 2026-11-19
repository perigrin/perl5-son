# SSA reading list: summaries

Summaries of every source on Max Bernstein's reading list
[A catalog of ways to generate SSA](https://bernsteinbear.com/blog/ssa/), read
and written up for chalk / B::SoN (2026-11-19). Each file follows one
template: what the paper says, its key ideas with a small example, its
construction algorithm, what it says about memory, arrays and aliasing, its
relevance to chalk / B::SoN, and its limits. Every summary covers the whole
paper; each opens with a note saying how it was read (text, or page images
for OCR'd scans). Anything that is the summariser's own reading rather than
the paper's is marked as an inference.

The papers themselves are not in this repository (publisher copyright); the
links point to the public copies Max hosts.

## The list, in the page's order

### Background

| Summary | Source | Central contribution |
|---|---|---|
| [zadeck-code-motion](zadeck-code-motion.md) | Cytron, Lowry, Zadeck, POPL 1986 ([pdf](https://bernsteinbear.com/assets/img/zadeck-code-motion.pdf)) | SSA before the phi notation: give every value its own name, mark "birthpoints" where values join; a may-write site is both a use and a definition, an external call a birthpoint for every external variable. |
| [zadeck-gvn](zadeck-gvn.md) | Rosen, Wegman, Zadeck, POPL 1988 ([pdf](https://bernsteinbear.com/assets/img/zadeck-gvn.pdf)) | Names SSA and the phi function; whole-procedure value numbering with trivial-phi removal and a phi-at-every-loop-header construction. |

### Constructing SSA

| Summary | Source | Central contribution |
|---|---|---|
| [cytron-ssa](cytron-ssa.md) | Cytron et al., TOPLAS 1991 ([pdf](https://bernsteinbear.com/assets/img/cytron-ssa.pdf)) | Dominance frontiers give minimal phi placement for any CFG. Section 3.1 models arrays as whole values (`Update`/`Access`) and the heap as one variable every possible write uses and redefines. |
| [brandis-single-pass](brandis-single-pass.md) | Brandis, Mössenböck 1994 ([pdf](https://bernsteinbear.com/assets/img/brandis-single-pass.pdf)) | SSA and the dominator tree in one pass while parsing structured code. |
| [kelsey-ssa-cps](kelsey-ssa-cps.md) | Kelsey 1995 ([pdf](https://bernsteinbear.com/assets/img/kelsey-ssa-cps.pdf)) | CPS and SSA translate into each other exactly; mutated variables become memory cells with stores and fetches, and get no phis. |
| [click-ssa](click-ssa.md) | Click, Paleczny 1995 ([pdf](https://bernsteinbear.com/assets/img/click-ssa.pdf)) | **The sea of nodes.** Region, If, Phi and Projection replace blocks; memory and I/O are separate threaded values; a Store makes a new memory version, a Load does not. |
| [click-gvn](click-gvn.md) | Click, PLDI 1995 ([pdf](https://bernsteinbear.com/assets/img/click-gvn.pdf)) | Global code motion places floating nodes between earliest and latest legal block, so value numbering is a hash pass -- correct only if every memory and fault dependence is an explicit edge. |
| [sreedhar-ssa](sreedhar-ssa.md) | Sreedhar, Gao, POPL 1995 ([pdf](https://bernsteinbear.com/assets/img/sreedhar-ssa.pdf)) | The DJ-graph places phis in linear time without building dominance frontiers. |
| [incremental-ssa](incremental-ssa.md) | Choi, Sarkar, Schonberg, CC 1996 ([pdf](https://bernsteinbear.com/assets/img/incremental-ssa.pdf)) | Exact repair of SSA after inserting or deleting a use or definition, with a bound on the affected region. |
| [appel-basic-block-arguments](appel-basic-block-arguments.md) | Appel 1998 ([pdf](https://bernsteinbear.com/assets/img/appel-basic-block-arguments.pdf)) | "SSA is functional programming": blocks are nested functions, phis their parameters. |
| [briggs-ssa](briggs-ssa.md) | Briggs, Cooper, Harvey, Simpson 1998 ([pdf](https://bernsteinbear.com/assets/img/briggs-ssa.pdf)) | Semi-pruned SSA, cheaper renaming, and correct phi removal (the lost-copy and swap problems); assumes a name never holds different types on different paths. |
| [aycock-horspool-ssa](aycock-horspool-ssa.md) | Aycock, Horspool 2000 ([pdf](https://bernsteinbear.com/assets/img/aycock-horspool-ssa.pdf)) | A phi for every variable in every block, then two deletion rules; no dominator tree. |
| [ssa-matrices](ssa-matrices.md) | Nguyen, Scholz 2007 ([pdf](https://bernsteinbear.com/assets/img/ssa-matrices.pdf)) | Dominance and frontiers as Boolean matrix equations: little code, good for prototypes and cross-checks. |
| [bebenita-ssa](bebenita-ssa.md) | Bebenita ([pdf](https://bernsteinbear.com/assets/img/bebenita-ssa.pdf)) | Build each block against placeholders, then link with forwarding pointers and phis; parallel copies on the way out. |
| [biggar-ssa](biggar-ssa.md) | Biggar, Gregg 2009 ([pdf](https://bernsteinbear.com/assets/img/biggar-ssa.pdf)) | On-demand SSA inside constant propagation, so alias analysis and SSA need not precede each other -- the PHP/Perl aliasing problem. |
| [pizlo-ssa](pizlo-ssa.md) | Pizlo's gists ([1](https://gist.github.com/pizlonator/79b0aa601912ff1a0eb1cb9253f5e98d), [2](https://gist.github.com/pizlonator/cf1e72b8600b1437dda8153ea3fdb963)); [Bril](https://capra.cs.cornell.edu/bril/lang/ssa2.html) | Phi split into Phi + Upsilon so the CFG knows nothing of SSA; memory, traps and state as reads/writes of a tree of abstract heaps. |
| [braun13cc](braun13cc.md) | Braun et al., CC 2013 ([pdf](https://bernsteinbear.com/assets/img/braun13cc.pdf)) | Pruned, minimal SSA straight from the syntax tree by asking "what is this variable's value here?", with sealed blocks and trivial-phi removal (Cranelift's construction). |
| [masud-ssa](masud-ssa.md) | Masud ([pdf](https://bernsteinbear.com/assets/img/masud-ssa.pdf)) | Dominance-frontier placement assumes every variable is defined at entry, giving many superfluous phis; reaching definitions place exactly the needed ones. |
| [lemerre-ssa](lemerre-ssa.md) | Lemerre ([pdf](https://bernsteinbear.com/assets/img/lemerre-ssa.pdf)) | SSA translation as an abstract interpretation, in one pass with value numbering and constant propagation; memory left to future work. |
| [ssa-without-dominance](ssa-without-dominance.md) | ([pdf](https://bernsteinbear.com/assets/img/ssa-without-dominance.pdf)) | Free-variable "nesting" in place of dominance; works for higher-order programs; no memory model. |

### Qualifiers, other papers and resources

| Summary | Source | Central contribution |
|---|---|---|
| [firm-ssa](firm-ssa.md) | libFIRM ([pdf](https://bernsteinbear.com/assets/img/firm-ssa.pdf)) | A production sea-of-nodes IR: Load and Store both consume and produce memory; `Sync` rejoins independent memory operations; dominance-free construction from the syntax tree. |
| [boissinot-out-ssa](boissinot-out-ssa.md) | Boissinot et al., CGO 2009 ([pdf](https://bernsteinbear.com/assets/img/boissinot-out-ssa.pdf)) | Correct out-of-SSA by parallel copies plus value-based coalescing; why phis at a join are simultaneous. |
| [wimmer-linear-scan-ssa](wimmer-linear-scan-ssa.md) | Wimmer, Franz, CGO 2010 ([pdf](https://bernsteinbear.com/assets/img/wimmer-linear-scan-ssa.pdf)) | Linear-scan register allocation that keeps SSA, folding phi removal into resolution. |
| [arxiv-2011.05608](arxiv-2011.05608.md) | [arXiv 2011.05608](https://arxiv.org/abs/2011.05608) | A scan allocator without intervals or interference graphs. |
| [ssa-book](ssa-book.md) | Rastello, Bouchez Tichadou (eds.), *SSA-based Compiler Design* ([draft pdf](https://bernsteinbear.com/assets/img/ssa-book.pdf); [Springer 2022](https://link.springer.com/book/10.1007/978-3-030-80515-9)) | The field's handbook. Our copy is a 2018 draft (19 of the published 24 chapters; no Hashed SSA chapter). |
| [cornell-lesson6](cornell-lesson6.md) | [Cornell CS6120 lesson 6](https://www.cs.cornell.edu/courses/cs6120/2022sp/lesson/6/) | Introductory lesson: SSA, phis, dominance-frontier construction. |
| [singer-ssa](singer-ssa.md) | [Jeremy Singer's SSA bibliography](https://www.dcs.gla.ac.uk/~jsinger/ssa.html) | 106 annotated papers; its Array SSA, heap, alias and SSI sections are the reading queue for chalk's deferred array and escape-analysis work. |

## What the literature says about our open questions

A first synthesis, from the summaries; the audit of B::SoN against this
literature (2026-11-19, to follow) goes deeper.

- **One memory chain is a documented design, not a shortcut.** Cytron
  (section 3.1) treats the heap as one variable that every possible write
  uses and redefines; the SSA book's Value State Dependence Graph threads one
  state edge through loads, stores and calls; it notes that for weakly typed
  languages the whole heap can be one array. Slicing memory (libFIRM's
  `Sync`, Pizlo's tree of abstract heaps, the book's heap arrays) needs
  proven disjointness, which Perl's references, aliasing and `tie` deny until
  escape analysis supplies it.
- **Every partial write reads the old memory version and produces a new
  one.** The book reaches this four ways (Array SSA's definition-phi, HSSA's
  chi, psi functions, the status-register rule); Click and libFIRM make Store
  consume and produce memory. Explicit Store/Load and "effectful node as the
  version" are equivalent in the book.
- **A write off the memory chain is a defect the theory can check.** Click's
  code motion is correct only if every memory dependence is an explicit edge;
  the VSDG's dead-node elimination, and Cytron's, delete anything not reached
  backwards from the exit along value and state edges -- so a floating write
  is by definition dead. The invariant: every memory-writing node is reached
  from the exit through its memory output.
- **Calls.** Zadeck 1986: an external call is a definition point for every
  variable it could touch; a may-write is both a use and a definition.
  libFIRM's Call consumes and produces memory and projects its results.
- **I/O and faults.** Click threads I/O separately from memory; libFIRM's
  table gives `Div`/`Mod` neither memory nor control, so it offers no model
  for a faulting division; Pizlo models traps as abstract-heap effects.
- **Typing.** Briggs assumes a name is type-consistent on every path, which
  Perl scalars violate; the book's chapter 11 says facts learned from uses or
  branch conditions need a new SSA name at that point (sigma functions,
  e-SSA), not a write-back onto the declaration -- the shape of B::SoN's
  typing-by-use bug.
- **Construction.** Braun et al. build minimal SSA directly from the syntax
  tree, with memory as one more variable; Kelsey: mutated variables become
  memory cells, not phis -- what B::SoN does for captured and address-taken
  scalars.
- **Arrays as values (deferred).** The book's chapter 14 (Array SSA) is the
  later escape-analysis layer nearly verbatim.
