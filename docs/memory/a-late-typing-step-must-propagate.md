---
name: a-late-typing-step-must-propagate
description: A pass that types nodes after the last propagation leaves their merges untyped; propagate again after it
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-13T16:30:00Z
---

Chalk's Analysis ends with `_type_calls_by_context`: a direct call inference
left untyped is Scalar (or List) by its context. It ran AFTER the last
`_seed_and_propagate_reprs`, so a Phi merging such a call stayed untyped and
the exit assertion refused the whole load ("untyped Value node: Phi in
X@scalar"). Seen in a per-context copy (`sub r { return $n if ...; return
g($n) }` called in scalar context), where the loader clears the returned call's
stamp and the Phis to the Return so Analysis retypes them.

**Why:** typing is a fixpoint; any step that stamps a node outside the
propagation loop breaks the fixpoint for that node's consumers.

**How to apply:** when adding a typing step after propagation, follow it with
`_seed_and_propagate_reprs`. When the assertion names an untyped Phi whose
inputs are all typed, look for a stamp written after the last propagation.
Test: chalk t/bootstrap/ir/t2-a-returned-call-typed-by-its-context.t.

Related: [[verify-the-harness-before-reading-its-output]]
