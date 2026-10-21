---
name: a-memory-phi-must-be-marked
description: The deparser cannot infer a memory Phi from its inputs -- a call is both a value and a memory version; the producer marks it
metadata:
  type: feedback
---

The deparser's `_is_memory` decided a Phi was a memory merge when any input
was. Two failures in one day: a depth-first walk cached 0 for a Phi still
pending on a loop cycle, so an inner loop's memory Phi read as a value and
was rendered as a loop variable whose init was a store; and the fixpoint
that replaced it spread memory-ness through `$cur = shift`'s latch merge,
because a `shift` call is a memory point too.

**Why:** a call is a value AND a memory version, so from inputs alone a Phi
over calls is undecidable. The producer knows what it built.

**How to apply:** Phi carries `memory => 1` on the wire (Serialize/JSON;
chalk's loader reads Phi fields by name and ignores it). Every memory Phi
site sets it -- loop header, loop exit, branch merge (StackSim). The
deparser takes Phis from the marker only; a Call is memory when its
`memory_input` is.
