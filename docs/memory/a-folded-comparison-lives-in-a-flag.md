# A folded comparison lives in a flag

**Lesson (2026-11-28, compiling stevan/curly examples/brainfuck.pl):** perl
5.28+ folds `index(...) >= 0`, `> -1`, `!= -1` and `== -1` into the index op
(OPpTRUEBOOL, OPpINDEX_BOOLNEG) and deletes the comparison op. B::SoN read the
raw position: position 0 false, -1 true -- silently wrong in the pushed code.
The fail-closed flag table (Q1/Q8) listed only flags that change what an op
STORES; a flag that changes what it RETURNS was outside it.

**Rule:** a private flag that changes an op's value is as much a fail-closed
case as one that changes its store. Fixed in ab5b0c29 (NumNe/NumEq of the
position and -1). Still to do: walk B::Op_private for every value-changing
flag and table it.

Also: a my scalar's post-op handed to a call (`f(--$x, $x--)`, promotion
off) -- the producer's value read and the store's location are one
hash-consed node, so the fix is chalk's: a non-place read at an older version
than its call is a copy (chalk e7d05dbe), as a package scalar's already was.
Real programs find what probes miss: run one end to end each audit.
