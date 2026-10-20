---
name: the-discriminating-property-is-arity
description: map/grep body contributions must be keyed on how many values they yield, not on node identity
metadata:
  type: project
---

A map/grep body runs in LIST context, so a contribution yielding N values must
arrive as N inputs to `ListAppend`. Appending one node that STANDS FOR N makes a
consumer counting inputs read 1.

This was fixed three times in 2026-09, each keyed on the wrong property:

    stamp (Hash/Array)   -> missed Slice, stamped Unknown
    node kind (+Slice)   -> missed reverse/sort, which are Calls
    ALLOW-LIST by arity  -> correct

**Why:** every member of the set is just "contributes != 1". Enumerating the
kinds that DO flatten is open-ended and fails silently as new ones appear;
enumerating the kinds KNOWN to yield exactly one fails safe.

The strongest evidence: `map { &{$sub}($_) } @{$array}` (comp/proto.t) — a call
through a coderef, arity not statically knowable even in principle. No
enumeration of list-producing shapes would have reached it; the allow-list
refused it by not recognising it.

**How to apply:** grep is unaffected and must NOT be caught — its body is a
predicate in boolean context, so its contribution is 0-or-1 regardless. When
list-return lowering lands, `map { agg() }` becomes live and the map walk needs
the callee's arity handled at the same time, not after.

See [[allow-lists-fail-asymmetrically]] for the trap in writing the list itself.
