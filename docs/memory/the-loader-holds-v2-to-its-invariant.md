---
name: the-loader-holds-v2-to-its-invariant
description: "Wire v2 stage 5: chalk's WireInvariant (L1-L6) on a native v2 wire, chalk's own wire-verify.t over its lib and probes; what each found in the producer, and why L5/L6 are V2's and the trap's at this stage"
metadata:
  type: project
---

Wire v2 stage 5 (2026-11-21). chalk `Chalk::IR::Serialize::WireInvariant`
runs in `from_json` on every graph of a wire that came as v2 (an upgraded
v1 is not held); `t/bootstrap/ir/wire-verify.t` runs the producer's
SoN::Verify over chalk's lib and its audit probes at wire 2.

**L5 and L6 as written would have refused census cases.** The plan's L5
(an Assign is a record or has all three of control_in, mem_in, mem_out; a
sub Call too) refused 167, 168 (`($lo, $used) = g()`: a pinned Assign that
binds `my` scalars, stores nothing) and the lvalue call of 398. The plan
itself makes L5 hard only in stage 6, and SoN::Verify's V2 asks only for
mem_in: L5 is V2's now. L6's arity refused 210: a string eval's trap joins
like a block eval's (one more input than ways in) but its Region has no
eval_id; that is the plan's `phi-arity` row, stage 8's. A trap is a Region
with eval_id or whose one way in is a pinned Coerce to Code.

**The verifier over chalk's sets found producer faults (each fixed, TDD):**

- V2 corpus 398: an :lvalue call made a store's location was taken off the
  control chain but stayed the memory version: `_unplace` takes back both.
- V5, 51 chalk graphs + 3 corpus + 3 probes, was the VERIFIER: on a wire
  without the `loop` profile a loop test's effects hang off the Loop beside
  the body's Proj 0, so the body follows the test's last version, not the
  Loop's memory Phi. The rest were real: a foreach body writing its alias,
  and a while body storing after an arm ending in `next` (or holding a
  loop), got no header memory Phi before the walk (`_body_stores_memory`
  stopped at the first `if`), so the second pass followed the entry memory.
- V7 probes lo12, m3, chalk lib: a void list assign storing package scalars
  by position left its Assign beside the EntryWrites, on neither chain.
  Held: pl13, the same Assign as its sub's value (what node that value is
  needs a design).
- An append's result `my` read had its store as a value input on v2 (probe
  ev10 refused on wire 2 only): one site said `inputs => [$store]`.

**How to apply:** a v2-only refusal or rule hit in chalk is as likely an
unconverted producer site (memory as an input) as a chalk question; dump
both wires (`mem_in` vs a trailing input) first.

Related: [[a-memory-edge-is-not-a-version]], [[the-wire-verifier-and-its-ratchet]].
