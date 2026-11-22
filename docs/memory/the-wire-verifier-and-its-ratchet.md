---
name: the-wire-verifier-and-its-ratchet
description: SoN::Verify checks the memory-chain rules on the wire; a ratchet holds the counts; what the current wire cannot express
metadata:
  type: project
---

`lib/SoN/Verify.pm` checks a decoded wire against the memory-chain rules of
the 2026-11-19 audit (step 2 of its section 5). `tools/wire-verify.pl` runs it
over the pvm corpus, the audit's probes and (`--chalk DIR`) chalk's lib;
`t/wire-verify-ratchet.t` fails if any rule's count rises above
`t/data/wire-verify-baseline.tsv`, or `#wires` falls. A fix that lowers a
count lowers its row in the same commit.

It catches every probe of the audit's classes W1, W2, W3, W10 and the two
floating divisions, and 7 of 8 of W4 (`st2`'s `blessed` carries a memory
input; its fault is elsewhere).

**Lessons from writing it:**

- **A place and a read are told apart by the consumer, not the node.** An
  unversioned `Subscript [c, k]` is a place when every use is an Assign
  target, a container, a sub-call argument or an operand of a builtin
  flagged `memory_input`; otherwise it is a read at no version. The first
  draft flagged a named package literal with ANY consumer but its
  EntryWrite: 26 hits, of which 20 were the container of a `Count` or `Subscript` that
  carries memory, or an operand of a memory-flagged `join` -- versioned reads. Read twenty hits of a new rule before baselining it.
- **A pinned read is versioned** by its control position (`FieldAccess [] ^0`),
  so "no memory input" alone is not the violation: no input AND no control_in.
- **"Reached backwards from Return" cannot be checked on this wire.** Return
  takes no memory and a Loop has no back edge, so a walk back from Return
  never enters a loop body; and a loop condition's effects (`shift` in
  `while (my $n = shift @w)`) are pinned to the Loop node itself, so they are
  leaves of the control chain that are not dead. The chain is checked forward
  from Start. A pinned write on a path that never rejoins is invisible until
  wire v2 names the memory edge.
- **`s///r` is a RegexSubst with `r` in `flags`** and no control_in: a value,
  not a floating write. Without that test chalk's lib read 77 false effects.
- **One eval join has no `eval_id`**: the string eval's (`eval '...' or die`,
  corpus case 210) is a one-input Region with a two-input Phi, so the audit's
  "33 eval joins" are 32 `phi-arity:eval-join` and 1 plain `phi-arity`.
- **The counts double-count library graphs**: a wire holds every module it
  loads, so Carp's graphs appear in three corpus wires and chalk's Builder in
  most of chalk's 218.

**Why:** the audit's finding 9 -- no checker can see a floating write -- and
its step 2. **How to apply:** run `prove -l t/wire-verify.t` after touching
the verifier; `tools/wire-verify.pl --list` to see each violation; use
`--wires DIR` to cache wires only while the producer is unchanged.

Related: [[the-memory-table-must-be-scraped]], [[make-the-guard-fail-on-purpose]],
[[a-memory-phi-must-be-marked]], [[verify-the-harness-before-reading-its-output]].

**Stage 10 (2026-11-22):** the ratchet is no ratchet any more: every rule is hard, the few that stay are held by name (t/wire-verify-ratchet.t `%HELD`), and the baseline holds only `#wires` and `#graphs` ([[a-held-count-is-not-a-held-name]]).
