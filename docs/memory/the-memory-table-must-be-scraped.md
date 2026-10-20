---
name: the-memory-table-must-be-scraped
description: Deparse's %MEM_MIN_INPUTS is a second copy of which nodes carry memory, and it drifted
metadata:
  type: project
---

`SoN::Deparse`'s `%MEM_MIN_INPUTS` says how many of a node's inputs are real
operands, so the TRAILING memory edge is not counted as a value. A kind
missing from it binds the node that produced its memory, then asks to render
a store as an expression:

    GAP: no rule for value node `EntryWrite`

`Exists` was missing while `Delete` — the same `[container, key, memory]`
shape one operator over — was present. The render branch's own comment
documented the shape correctly; only the table was wrong.

**It is a second copy of a fact FromOptree owns.** `t/deparse-memory-table-
matches-producer.t` scrapes the producer for `make('Kind', inputs => [...memory...])`
and fails if any kind is absent from the table, so the two cannot drift again.

The authoritative list as of that test: Call, CellRead, CellWrite, Count,
Delete, EntryWrite, Exists, MakeCell, PostfixDeref, RegexSubst, Subscript,
Transliterate.

Related: [[allow-lists-fail-asymmetrically]], [[assign-targets-are-positional]].
