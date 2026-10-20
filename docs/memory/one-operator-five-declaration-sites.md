---
name: one-operator-five-declaration-sites
description: Adding an IR operator means editing five sites in four files; each omission fails differently and late
metadata:
  type: project
---

**Adding one operator to B::SoN's IR means editing FIVE declaration sites
across four files**, and nothing makes the compiler check that they agree:

1. `lib/SoN/FromOptree/OpMap.pm` — optree name → pop/node/push/flags
2. `lib/SoN/IR/Node/<Name>.pm` — the node class
3. `lib/SoN/IR/NodeFactory.pm` — a `use` line AND a name in a `qw()` list
4. `lib/B/SoN/TypeLibrary.pm` — `operands`, `result`, `%RESULT_IS_JOIN`
5. `lib/SoN/FromOptree.pm` — `%RESULT_STAMP`

Each omission fails **differently and late**: (1) silent fall-through, (2)/(3)
factory death, (4) operands never coerced, (5) node reaches the wire stamped
`Unknown`.

Measured 2026-08-31: OpMap names **47** IR nodes, TypeLibrary declares **39**
signatures, `%RESULT_STAMP` holds **19**.

This is a KNOWN defect, recorded twice before: `TypeLibrary.pm`'s header says
*"Three partial copies of one table, none of them labelled as such"*, and
commit `93a2d12` found the fourth copy while adding `Count` (which came out
`Unknown` because TypeLibrary was updated but `%RESULT_STAMP` was not).

**Gates exist now** (`2bb1495`): `t/every-op-has-a-disposition.t` and
`t/op-declaration-sites-agree.t`. Both verified to fail when a half-added op is
injected. They do not fix the duplication — they stop it widening.

**Plan:** `docs/plans/2026-08-31-one-operator-one-declaration.md` — collapse to
one entry per operator with everything derived. Do NOT reach for Allium-style
extraction from perl for this: it generates only the structural third, and op
churn is tiny (5.38→5.44 added 8 ops, removed 0).

Related: [[allium-instruction-sets]], [[crashes-mask-gaps]]
