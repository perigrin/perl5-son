# Constructing SSA the Easy Way

**Authors, venue, year.** Michael Bebenita, University of California, Irvine. Informal note dated 2 November 2009 (not a refereed publication).  **Source:** https://bernsteinbear.com/assets/img/bebenita-ssa.pdf

*Extraction note: the figures are diagrams and came through as scrambled text; the prose and the pseudocode (Algorithm 3) are intact.*

## In one paragraph

A ten-page recipe for getting into and out of SSA (static single assignment: each variable assigned once) with as little machinery as possible. The trick is to pretend every basic block is a small function whose parameters are "the value of each local variable on entry". Build each block on its own against those placeholder parameters; afterwards connect each placeholder to what the predecessor blocks actually leave in that variable, inserting a Phi (a "pick the value from the path we came by" node) when predecessors disagree. A "forwarding pointer" on every instruction makes replacing one value by another a one-line operation. The author describes it as a rehash of Aycock and Horspool's algorithm using forwarding pointers.

## Key ideas (intuitive first, then the mechanism; one small worked example)

**State vector.** At any program point, a list saying which SSA value each local variable currently holds: `{v0, v1, ..., vn}`. An assignment overwrites a slot; a read returns the slot.

**Forwarding.** Each instruction has a `forward` field. `forward(i, j)` means "i has been replaced by j". Every time you look at an instruction you first call `resolve(i)`, which follows the chain to its end and shortcuts it. This replaces the bookkeeping of "find every user of i and rewrite it".

Worked example. Variables `x`, `y`; three blocks:

```
A:  x = 1          if c goto B else goto C
B:  y = x + 1      goto D
C:  y = 5          goto D
D:  print y
```

1. Give each block placeholder entry values: `A0,A1` ... `D0,D1` (slot 0 is x, slot 1 is y).
2. Build each block alone. D becomes `print D1`; its exit state is `{D0, D1}`. B's exit state is `{B0, (B0+1)}`; C's is `{C0, 5}`.
3. Link. B and C have one predecessor (A), so `B0` forwards to A's exit value for x, i.e. `1`. D has two predecessors: slot 1 gets `phi(B0+1, 5)` and `D1` forwards to that Phi; slot 0 gets `phi(1, 1)`.
4. Simplify: `phi(1, 1)` has all-equal inputs, so forward it to `1` and delete it.

## Construction / algorithm (steps, complexity, inputs it needs)

**Inputs:** a complete set of basic blocks with predecessor lists. No dominator tree.

1. For each block: create an entry state vector of placeholders; run `constructSSA(entryState, block)`, which abstractly interprets the block's instructions, emitting SSA instructions and returning the exit state vector.
2. For each block and each variable slot: collect that slot from each predecessor's exit state. One value: forward the placeholder to it. More than one: create a Phi over them, forward the placeholder to the Phi, put the Phi at the top of the block.
3. For each Phi whose resolved operands are all equal: forward it to that operand and remove it.

No complexity analysis is given. (My observation: step 2 creates a Phi for every variable at every join before pruning, so the temporary cost is blocks times variables; and step 3 as written is a single pass, which will not remove Phis that only become trivial after others are removed, nor Phis that refer to themselves round a loop. Aycock and Horspool iterate to a fixed point.)

**Getting out of SSA.** Replace each Phi by moves at the end of the predecessor blocks. All Phis of a block conceptually happen *at once*, so the moves form a "parallel copy" and must be ordered so no value is overwritten before it is read; a cycle such as `x<-y, y<-z, z<-x` (which copy propagation readily creates) needs one temporary. Before any of this, split *critical edges* (an edge from a block with several successors to a block with several predecessors) by inserting an empty block, so the moves have a safe place to live.

## Memory, arrays, aliasing (what it says, or "not addressed")

One remark only: tracking data flow through "arbitrary memory access" is "also possible and much more complicated" because of aliasing, and would need "aggressive escape analysis" and alias analysis. The state vector can hold "anything you choose to track dataflow for". Nothing further.

## Relevance to chalk / B::SoN (concrete: what to adopt, what it warns about, what does not apply)

- **The state vector is the right mental model for B::SoN's walk**, and the remark that it can hold anything you choose is the hook for memory: add slots for "current memory" and "current I/O" next to the lexical scalars and they get Phis at joins by the same code. (Inference.)
- **The escape-analysis remark supports chalk's ordering of work:** containers in memory now, array SSA only after escape analysis.
- **Forwarding pointers** are a cheap alternative to def-to-use lists for "replace node A by node B", useful in a Perl implementation where maintaining use lists is slow. The warning in the paper applies: every access must go through `resolve`, or stale nodes leak. A stale memory node is exactly a write off the chain.
- **Prefer Braun et al. for the actual algorithm:** it produces the same shape lazily, without creating a Phi per variable per block first, and handles loops properly.
- **Out-of-SSA section does not apply:** T2 emits LLVM IR, which has Phis. The parallel-copy and critical-edge points only matter if chalk ever targets something without Phis.

## Limits and later work

Informal, unproven, no measurements. Phi pruning is incomplete as written. Superseded for practical purposes by Braun et al. (CC 2013); the out-of-SSA half is treated rigorously by Boissinot et al.
