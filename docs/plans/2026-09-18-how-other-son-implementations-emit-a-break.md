# How other Sea-of-Nodes implementations represent a loop break

perigrin asked how this is done elsewhere, and then to check what "irreducible
flow" actually means here. Researched rather than recalled: I had no V8, Graal
or HotSpot sources on this machine, and the house standard for a prior-art
claim is `Parameter.pm`'s file-level citation ("common-operator.cc, verified
verbatim"). Sources are listed at the end.

## THERE IS NO BREAK NODE

A break is an ordinary control edge into the loop's exit Region. No vocabulary,
no marker, no node kind. Our producer already builds exactly this -- measured on
`while ($i<5) { $i++; last if $i==4; $s += $i }`:

    Region 17 preds: [8, 16]
      Proj 8  index 1  <- Loop(3)    the header-false exit
      Proj 16 index 0  <- If(15)     the break

Cliff Click's reply to V8's "Leaving the Sea of Nodes" makes the general point:
loop work is "standard SCC, finding loop headers, walking the graph area
constrained by the loop", not special representation. He treats V8's
control-flow complaints as implementation choices rather than properties of the
IR.

## WHY JITS NEVER HIT OUR PROBLEM

HotSpot C2, Graal and TurboFan lower a Region to a basic-block label; the edges
become machine branches. Nobody asks them to emit `last`. The problem only
exists for a consumer whose TARGET IS A STRUCTURED LANGUAGE -- which is what
our deparser is, and what WebAssembly and JS backends are.

Those solved it with Relooper (Emscripten) and Stackifier (LLVM's wasm
backend). The rule, from the Leaning Technologies write-up:

    "once a loop starts all the subsequent blocks must be dominated by the loop
     header, until all the loop blocks have appeared"

    "labeled breaks emerge from non-consecutive forward edges in the
     dominance-respecting topological order"

So an edge is a BREAK when it is a forward edge whose source is inside the loop
and whose target is outside. Decided by DOMINANCE AND LOOP MEMBERSHIP, not by a
mark on the edge. Back edges become `continue` by the same reasoning.

## WHAT THIS DECIDES FOR US

The discriminator is structural and already present:

    Proj 8  <- Loop      the source IS the loop header      normal exit
    Proj 16 <- If(15)    the source is dominated by Loop    BREAK, emit `last`

So: NO NEW IR VOCABULARY AND NO WIRE CHANGE. The break edge is recoverable the
way every structured-output compiler recovers it.

This is the opposite of the `EntryWrite.binds` case, and the difference is worth
keeping straight. There, a store and a binding were genuinely indistinguishable
-- same node kind, same memory chain -- so the producer had to say which.
Here the two predecessors differ in what dominates them, so a consumer can
derive it and a marker would be redundant.

The fix is therefore purely T2, in `_emit_loop`: for each exit-Region
predecessor, if its source is dominated by the Loop, emit `last;` on that arm
instead of inlining the continuation.

## THE REDUCIBILITY CAVEAT, AND MY WRONG CLAIM ABOUT IT

Stackifier "works only on reducible control-flow graphs", so it is worth being
precise about what that excludes.

A CFG is REDUCIBLE when removing every back edge leaves a DAG in which every
node is still reachable from entry. Equivalently: every cycle has a SINGLE
ENTRY POINT, its header. IRREDUCIBLE means a cycle with TWO OR MORE entries --
you can jump into the middle of a loop from outside without passing through its
header. That is what breaks the analysis: "an irreducible loop cannot be handled
in standard ways for most optimizations", because there is no unique header to
hang the loop's Phis and dominance facts on.

I claimed "Perl's `goto &sub` and `goto LABEL` can produce irreducible flow".
Measured, BOTH HALVES ARE WRONG:

    goto INTO a loop body        perl REFUSES it outright:
      "Can't \"goto\" into the middle of a foreach loop"
      and jumping into a construct is deprecated and FATAL as of 5.42

    goto LABEL backwards         a cycle with ONE entry (the label) -- reducible
      AGAIN: $n++; goto AGAIN if $n < 3;    prints n=1 n=2 n=3

    goto &sub                    a TAIL CALL, not a jump -- it replaces the
      frame, so it is an inter-procedural transfer and cannot make an
      intra-procedural CFG irreducible at all

The standard statement is that structured constructs -- for, while, if/else,
and `break`/`continue` included -- always keep control flow reducible. Perl's
loop controls are exactly those, and the one construct that could create a
second entry is the one perl itself rejects.

So the reducibility caveat is real in general and does not bite us. We are
inside the reducible subset by construction, not by luck. Worth stating
because the Stackifier rule depends on it, not because we need to guard
against it.

## Sources

- V8, "Land ahoy: leaving the Sea of Nodes"
  https://v8.dev/blog/leaving-the-sea-of-nodes
- Cliff Click, "A Simple Reply"
  https://github.com/SeaOfNodes/Simple/blob/main/ASimpleReply.md
- Leaning Technologies, "Solving the structured control flow problem once and
  for all"  https://labs.leaningtech.com/blog/control-flow
- Ramsey, "Beyond Relooper: recursive translation of unstructured control flow
  to structured control flow"  https://dl.acm.org/doi/abs/10.1145/3547621
- Hecht & Ullman / standard CFG reducibility, via
  https://en.wikipedia.org/wiki/Control-flow_graph and
  https://www.cs.tufts.edu/~nr/cs257/archive/jeff-ullman/reducibility-siam.pdf

Claude-Session: https://claude.ai/code/session_01QYtFNnt2aXaRH2hrRvopyc
