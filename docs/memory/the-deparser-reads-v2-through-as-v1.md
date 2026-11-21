---
name: the-deparser-reads-v2-through-as-v1
description: "Wire v2 stage 4: SoN::Wire::as_v1 puts a decoded v2 wire in v1's shape for the deparser; it cannot be exact (the wire does not say which mem_in was an operand), so it is measured by rendering, not by bytes; the exit memory Phi needed a field"
metadata:
  type: project
---

Wire v2 stage 4 (branch `v2-s4`, 2026-11-21). `SoN::Deparse::render` calls
`SoN::Wire::as_v1` on a `version: 2` wire. as_v1 moves `mem_in` back to the
end of `inputs` where v1 had it, sets a builtin Call's `memory_input`, drops
`mem_in`/`mem_out`/`record`, takes a MakeCell off the chain (as the v1 writer
does), drops the `exits` memory Phi and what only a `mem_in` reached (a
MemStart), and renumbers.

**Lessons:**

- **The wire does not say which `mem_in` was an operand.** The producer knows
  (`mem_operand`: memory given to `make`, not set by `_pin`). Measured with a
  wrapper that tagged each node (`-MMoTag`, scratch only): a node that only
  follows memory (Assign, sub Call, Return, Unwind, LocalAlias, Match) never
  had it; an ordered builtin Call, Ref or FieldAccess pinned without
  `mem_out` did not either; every other read did. About 30 builtin calls in
  9000 are the same kind and shape either way (4-arg substr, `$#a = N`, half
  the sorts with a comparator and the printfs). Measure a rule before
  writing it; say where it is wrong.
- **So prove it by rendering, not bytes.** Over corpus and probes, every
  v2 wire renders as its v1 wire does up to names made from node ids
  (`$stale10` -> `$stale12`: v2 lists a node's memory before it), or the two
  renderings print the same; one probe (ev6) renders broken the same way
  from both. Compare names by first appearance, and `$phi27_next` has the id
  mid-name.
- **A Phi only a Return names is two things on the wire.** The memory Phi
  where a sub's exits merge is `v2_only` (v1 has no place for it); a merge's
  memory Phi a Return names is in v1. Dropping both by shape lost real Phis;
  keeping both made the deparser refuse a sub (corpus 129). v2 now says
  which: `fields.exits` on the Phi.

Related: [[the-wire-names-its-memory-edges]], [[a-cell-is-a-version-made-where-it-stands]].
