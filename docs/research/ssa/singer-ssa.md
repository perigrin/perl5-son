# SSA Bibliography (Jeremy Singer) (resource note)

**Authors, venue, year.** Jeremy Singer (University of Glasgow). A web page generated with bibtex2html listing 106 papers, most read during his PhD; entries run from 1969 to 2013, the bulk from 1995-2003.  **Source:** https://www.dcs.gla.ac.uk/~jsinger/ssa.html

## In one paragraph

Not a paper but an annotated reading list of the SSA literature, grouped by topic, many entries carrying a short personal comment ("my, perhaps immature, opinions at that time"). It is the quickest way to find the original source for a named SSA variant.

## Key ideas (intuitive first, then the mechanism; one small worked example)

No technical content of its own. What it catalogues, section by section:

- Compiler textbooks (Appel, Muchnick, Cooper and Torczon, and others).
- SSA construction papers (Cytron et al., Brandis and Mössenböck, Aycock and Horspool, Braun et al. 2013).
- Pre-SSA historical papers.
- SSA extensions: Array SSA, dynamic single assignment, may-alias information in SSA, Hashed SSA.
- Interprocedural SSA.
- Static Single Information (SSI: variables are also split at branches, so a fact learned from a condition gets its own name) and its applications.
- Static Single Use; Linear Naming.
- SSA applications; SSA-based and SSI-based compilers; SUIF.
- Translating SSA into functional programs.
- Gated Single Assignment and the Program Dependence Web (Phis that record the choosing condition).
- SSA and type checking.
- SSA and code generation: register allocation and out-of-SSA translation (Briggs, Sreedhar, Boissinot).
- SSA for Java programs.

## Construction / algorithm (steps, complexity, inputs it needs)

Not applicable; see the construction section's entries.

## Memory, arrays, aliasing (what it says, or "not addressed")

Useful as an index. Singer's notes: Array SSA (Knobe and Sarkar, 1998) "extends SSA form to handle arrays more elegantly"; Fink, Knobe and Sarkar (2000) split classes "into heap-arrays of appropriate fields" indexed by object reference, then apply Array SSA to remove redundant loads and stores; Cytron and Gershbein (1993) on may-alias is "really simple"; Chow et al. (1996) give Hashed SSA for indirect memory operations.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- The "SSA extensions" section is the reading queue for chalk's deferred Array SSA and escape-analysis work. One heap-array per field is close in spirit to alias-class slices of the memory chain. (Inference.)
- The SSI entries bear on T1's integer intervals: after `if ($i < 10)` the true branch knows more about `$i`. (Inference.)
- Nothing on sea of nodes or memory-as-a-value designs (Click, libFIRM).

## Limits and later work

Personal, dated, thin after 2004; old links may be dead. For current coverage see Max Bernstein's catalogue, which this note belongs to.
