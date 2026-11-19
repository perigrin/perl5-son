---
name: the-effect-table-is-the-one-statement
description: "B::SoN::EffectTable says what each builtin writes and reads; the walk pins by it in every context and SoN::Verify reads it. A count can fall because the checker stopped looking"
metadata:
  type: project
---

Step 4 of the 2026-11-19 audit's plan, second half (branch `placement`,
f68e03a). `lib/B/SoN/EffectTable.pm`, keyed by perl op name (the `name` a
builtin Call carries: `prtf`, `dofile`), holds three facts per builtin --
`writes`, `reads` (handle, stack, variable, object-class, external),
`version` -- and answers `on_chain($name, lvalue => ...)` and
`is_version($name)`. Seven `%..._BUILTIN` sets in SoN::FromOptree and two
lists in SoN::Verify are gone; `t/effect-table.t` fails if one comes back.

A `writes` builtin is pinned in every context now, not only void: open,
close, bless, printf, mkdir, chdir, unlink, system and the rest.

**Lessons:**

- **A count can fall because the checker stopped looking.** Moving the
  verifier onto the table dropped corpus `read-unversioned:object-class` from
  68 to 50: the table had no row for `reftype_of_ref` (the walk's name for
  `ref \$x`), which the verifier's own list had. Diff every row that moves,
  not only the ones you meant to move.
- **Two lists drift.** The verifier's said `printf`; the wire says `prtf`. A
  floating printf was never flagged in three weeks of counts.
- **chalk c1a48dfe takes a pinned `bless` or `open` used for its value**
  (bless2 turned SAME, nothing regressed), **but not a pinned `printf` used
  for its value** ("a statement Call builtin prtf", probe ef30). The census
  and the 418 probes had no such program. A new pin is a new statement kind
  to the consumer: probe each one.
- **Not on the chain yet:** a backtick, chomp or s/// used for its value
  (their own node kinds, their own handlers), `ref`/`blessed`/`time` reads
  (no place for a version on this wire), and the dynamic method call (see
  [[a-pin-the-consumer-cannot-lower-is-held-back]]).
- `mkdir($d)` with one argument is an INTERNAL ERROR (OpMap says it pops
  two): older than this work, loud, not fixed here.

Related: [[the-wire-verifier-and-its-ratchet]],
[[one-constructor-places-every-node]], [[the-memory-table-must-be-scraped]].
