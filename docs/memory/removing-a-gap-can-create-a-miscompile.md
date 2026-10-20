---
name: removing-a-gap-can-create-a-miscompile
description: "Turning a producer refusal into a graph exposes it to consumers that may silently render it wrong; check the round trip, not the wire tests"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-17T03:54:08.289Z
---

When a GAP is removed so a construct now translates, the wire tests going green
proves only that the GRAPH is right. Each consumer must also be able to lower
it -- and a consumer with no rule for the new shape may not refuse, it may
render something plausible and wrong.

Measured: making `*crackers = \@SRC` translate produced a correct graph, and
the deparser rendered the binding as an ordinary store --
`@main::crackers = \(@main::SRC);` -- which runs and prints nothing where perl
prints `1 2 3`. All wire tests passed throughout. That trades a refusal for a
silent miscompile, which [[a-silent-drop-is-worse-than-a-refusal]] ranks as the
worst outcome.

**Why:** a producer refusal is load-bearing for consumers that were never taught
the construct. Removing it hands them input they have no rule for, and "no rule"
is only safe if the consumer refuses rather than guesses.

**How to apply:** when a GAP stops firing, run the round trip on the newly
translating shapes before believing the suite. If a consumer needs a new rule,
the producer may also need a wire field to distinguish the case -- here
`EntryWrite.binds`, because `$g = \@a` (store) and `*g = \@a` (bind) are the
same node kind over the same memory chain.

Related: [[read-generated-output-not-tests]], [[crashes-mask-gaps]]
