---
name: graph-correctness-needs-the-optree-not-the-source
description: Verify a B::SoN graph against the OPTREE, never the source; node counts prove nothing
metadata:
  type: feedback
---

When auditing a B::SoN graph for correctness, compare it against the OPTREE
(`perl -MO=Concise,-exec`), never against the Perl source. B::SoN's input is the
optree, and perl has already constant-folded, inlined and deleted code by then.

**Why:** I reported four bugs in t/base/translate.t's graph -- vanished calls,
`NumNe(x,x)`, an adrift PadAccess, a bad Phi -- and all four were misreadings.
`utf8::native_to_unicode` is a compile-time-inlined builtin that is the identity
on ASCII, so perl folds both calls and the whole `elsif` away before B::SoN sees
an op. `NumNe(x,x)` was correct.

Two related traps from the same session:

- A node with no `inputs` consumer is not necessarily dead. A written loop
  header condition attaches to its Loop by `control_in` (deliberately, so the
  consumer recovers it structurally rather than by a heuristic). Reading
  liveness by `inputs` alone reports a live node as dead.
- "Translates without error" is not "translates correctly". while.t emitted 58
  nodes with 0 GAPs while I still had to check all four loops by dataflow.

**How to apply:** dump the optree first, then read the graph against it. State
the expected value, trace the graph to it, and only then claim correctness.

Related: [[tbase-coverage-is-the-producer-corpus]]
