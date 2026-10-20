---
name: never-write-an-optree-constant-from-memory
description: OPf_* flag values recalled rather than queried were wrong three times in one fix; ask B for the number
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-18T10:21:06.242Z
---

Every optree flag constant must come from `B`, not from recall. Measured on
5.42.0:

    B::OPf_WANT_VOID()    1
    B::OPf_WANT_SCALAR()  2      (I wrote 1 -- handler never fired)
    B::OPf_WANT_LIST()    3
    B::OPf_REF()         16
    B::OPf_MOD()         32      (I wrote REF|MOD as 12 -- excluded nothing,
                                  broke 10 test files)

**Why:** a wrong constant fails in two opposite directions and neither looks
like a wrong constant. Too-low and the guard never fires, so the construct
looks unhandled. Too-broad and it swallows unrelated shapes, so a *different*
feature breaks and the suite blames the wrong change.

**How to apply:** before writing any `$op->flags & N` test, run
`perl -e 'use B; print B::OPf_WHATEVER()'` -- it costs seconds. Then read the
actual op with `-MO=Concise,-exec` and confirm the flag letters (`s`, `K`,
`RM`) match what the guard expects on BOTH the case you want and one you must
not catch. `RM` = OPf_REF|OPf_MOD = "the aggregate itself is wanted" (a
foreach bound, an lvalue), which is the usual thing a count/deref guard must
exclude.

Related: [[a-guard-can-measure-the-wrong-quantity]],
[[verify-graphs-against-the-optree]]
