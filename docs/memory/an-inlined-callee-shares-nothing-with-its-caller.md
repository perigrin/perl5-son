---
name: an-inlined-callee-shares-nothing-with-its-caller
description: Inlining a callee whose body branches, loops or stores (chalk 4e1e9969..e1a15d3a) moved 106 census cases to their next refusal for +1 ROUNDTRIP; review found wrong answers from anything shared between caller and callee — nodes, caches, var_table, types
metadata:
  type: feedback
---

**The census result.** The cause "callee has effect(s) on its control
chain" fell from 106 to 0, but ROUNDTRIP rose only from 75 to 76. 105 of
the cases reached their next refusal:
- 50: `my (...) = @_`
- 19: the Assign-target rule
- 6: early returns
- the rest spread across other causes

A census counts each case by its first refusal, so clearing a cause tells
you nothing about round-trips. The goal now measures ROUNDTRIP instead.

**What the review found.** Wrong answers, all in shapes the corpus does not
hold. Every one came from something the inlined callee shared with its
caller:
- **Nodes.** Analysis.pm's coercion passes used one NodeFactory for all
  graphs. Ids are per graph, so f's `Coerce(shift#2)` and main's
  `Coerce(g(5)#2)` hash-consed to one node, and f tested main's value.
  Fixed with one factory per graph.
- **Caches.** The straight-line inliner lowered effects under a fresh cache
  and the value under the caller's, so a call ran twice.
- **var_table.** A copy of the caller's let callee `VarDecl#1` read caller
  `VarDecl#1`.
- **Types.** The callee's value is in its own repr and the call has the
  caller's. They need a coercion at the inline.
- **Graph walks.** Following every consumer leaves the callee through shared
  nodes.

The fix for the first of these exposed the last (an Int value where the
caller expected a Num), which the verifier caught.

**How to apply:**
- When inlining or splicing one graph into another context, assume
  nothing is shared: nodes, id-keyed tables, variables or reprs.
- Probe two callees in one expression, one callee twice, nested calls,
  and a callee beside another call, each with different arguments.
- Tests for shapes that lower must demand exact output. A test that
  accepts "or refused" hides regressions back to refusal.
