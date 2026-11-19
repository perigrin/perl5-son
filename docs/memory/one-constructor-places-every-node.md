---
name: one-constructor-places-every-node
description: "_pin and _place are the only way a node gets onto the control chain and the memory chain in SoN::FromOptree; a source test holds it; the refactor was proved by byte-identical wires"
metadata:
  type: project
---

Step 4 of the 2026-11-19 audit's plan, first half (branch `placement`,
32a14ca). `SoN::FromOptree` had about 100 hand-written placements, three
lines each (`set_control_in`, `set_control`, `set_memory`). They are two subs:

- `_pin($sim, $node)`: control_in from the current control, and the node
  becomes the current control. For what is ordered and makes no version (a
  Print, an Unwind, a may-die read, a call whose barrier `_call_memory_barrier`
  decides).
- `_place($sim, $node)`: `_pin`, then the node is the current memory.

`t/placement-one-constructor.t` fails if any line outside `_pin` takes
`control_in` from a sim's control.

**What it does not do:** the kinds that also carry memory as an input
(EntryWrite, CellWrite, Delete, a flagged builtin Call) still take
`$sim->memory` where they are built. Naming that edge is wire v2 (`mem_in`).

**Lessons:**

- **Prove a mechanical refactor by the wire, not the suite.** The 418 audit
  probes produced byte-identical JSON before and after (`cmp` on each). That
  took two minutes and said more than the nine-minute suite.
- **A regex rewrite over 24k lines needs its leftovers listed.** The three-line
  pattern caught 97 sites; the 13 it missed (a comment between the lines, an
  `if defined`, an Unwind's two extra calls) were found by grepping for what
  remained, then done by hand.
- **`set_memory($x)` and `set_memory($x) if defined $sim->memory` were mixed.**
  Only the condition scout's sim has no memory, and it is thrown away, so the
  one form `_place` uses (`if defined`) changed nothing.

Related: [[the-wire-verifier-and-its-ratchet]], [[a-list-assign-is-placed-by-where-its-targets-live]].
