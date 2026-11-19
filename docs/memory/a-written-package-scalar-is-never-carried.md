---
name: a-written-package-scalar-is-never-carried
description: "A package scalar some sub writes gets no loop value Phi and no forwarded binding in an op=; it is read at a memory version. What that cost the deparser, and the scout's string placeholders"
metadata:
  type: project
---

W1 of the 2026-11-19 audit (branch `placement`, 83bdf64, 72d047c, 0f090ac).
`our $g; sub bump { $g += 10 } for (1..3) { $g = $g + 1; bump() }` printed 13
for 33: the loop carried `$g` on a header Phi (`@LOOP_PHI_KEYS`), a copy no
callee's store reaches. The exception predated loop memory Phis.

- `_key_lives_in_memory($key)`: a `$Pkg::name` key that
  `_package_scalars_written` names, and no foreach alias. The scout does not
  return it as loop-carried, and `_refuse_unscouted_writes` skips it. One
  definition for both, or the walk refuses "a write its scout missed".
- `_entry_live_value($factory, $sim, $entry)`: the old value of every `op=`.
  NOT in the audit: outside any loop, `.=` read the scope binding and `+=`
  the bare unversioned name, so `$s .= "-"; ap("a"); $s .= "-"` appended to
  what `$s` held before the call (perl `-a-b`, the wire `--b`).
- `@LOOP_PHI_KEYS` is now empty for user code; it still holds keys of
  scalars only non-user library code writes.

**Lessons:**

- **The wire has two consumers.** The fix was right for chalk (10 probes
  WRONG -> SAME) and broke SoN::Deparse five ways, one of them a wrong answer
  (`$stale17` assigned only after its store: 6 for 7). The suite found it, not
  the probes. A read at a loop's memory Phi is "the value the pass starts
  from": `_bind_at_pass_top` binds it, for an EntryDef as for a shared lexical.
- **Do not widen a shared walk to fix one shape.** I made the deparser's
  "condition's own reads" closure stop at memory Phis; a `while` whose test
  is a diamond had been relying on that walk, and read its temporary before
  the body assigned it. The real cause was one check over: the refusal
  counted a store in ANY loop's body as ahead of the read.
- **Bisect with the test, not a reproduction of it.** My round-trip script
  said DIFFERS on every snapshot, base included, for a program the suite
  passed: it ran the producer with other options. `prove` in each snapshot
  directory gave the answer in a minute.
- **The loop scout's placeholders are string Constants** (`value => 'scout'`).
  A refusal keyed on "a string constant bound" (a foreach over `"a".."c"`)
  fired in the scout for `1..$i`, stopped it early, and surfaced as "a loop
  body writes a variable its scout missed (1)". Guard such checks with
  `!$IN_SCOUT`.
- **A foreach over a range of strings was a count from 0 to 0.** Found
  because tp7 stayed wrong after its W1 cause was fixed. A probe can hold two
  bugs; re-read the wire of one that does not turn.

Related: [[the-wire-verifier-and-its-ratchet]],
[[one-constructor-places-every-node]], [[a-memory-phi-must-be-marked]].
