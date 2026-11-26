---
name: the-third-final-audit-s-items-needed-whatever-the-alias-design
description: "Branch audit3-base: the third final audit's items that do not wait on the alias design (A/B/C) -- no store dropped (V13), tr/// in the store scans (EffectTable::bound_target), local undef / conditional / delete local, corpus 398's call on the chain, the verifier's alias rules in the loader (L11), writer:chalk only memory-free, a module start-up named on the wire (start_up); y probes gated (1263), 86 WRONGs in the alias classes / N12 left out and listed"
metadata:
  type: project
---

Branch `audit3-base` (2026-11-25; baseline section 28) in both repos (chalk rebased onto b5dd5571); gates6 all PASS: census 426, corpus 222, deparse 430, held 0, 4442 probes WRONG 0. The
third final audit (docs/research/2026-11-25-memory-model-final-audit-3.md)
found 146 WRONG in 1373 probes (probes/y). The user is choosing between A
(deny by default), B (places everywhere) and C (keep patching) for the
alias classes; this branch did the rest.

| item | outcome |
|---|---|
| 1 no store dropped | `_returns_its_target` (an assignment, op=, TARGMY, multiconcat, pre-increment, list assign) asked at the two sinks that need a place: a list assignment's target and an alias list's item; the alias-written test asks the one table (ModSets::stores_var). N6 13 WRONG -> 13 REFUSED. SoN::Verify V13 `store-into-value` (an Assign's target is a place); `effect-floating` now asks of a sub call too |
| 2 tr/// | `B::SoN::EffectTable::bound_target`: `$x =~ tr///` is null[target, trans], the target the elder sibling (s///'s is its kid). ModSets::_stores and the element scan ask it |
| 3 local $g; | stores undef where no assignment is its target |
| 4 corpus 398 | the :lvalue call stays on the chain (`_unplace` deleted); chalk L5 lost its exemption |
| 5 loader alias rules | ported: chalk `WireAliases` (L11), both halves of V12, whole-wire, one commit (it may move into one verifier over T1 later); a test holds it to the verifier |
| 6 writer: chalk | lets off only a provably memory-free wire; six chalk test fixtures threaded as v2 (chalk's front end not touched: threading memory there is a later project) |
| 7 N9 | B::SoN names a start-up not on the wire (`start_up`): INIT/CHECK blocks, a module's END, a module's file-level effect, an import storing elsewhere, a program BEGIN calling a module sub, and -- for a module the program reaches -- file-level state CHECK does not hold (a file lexical, a reference, a call, code made or loaded, an object, a tie, a glob; B::SoN::StartUp compiles the file again in a child). A store into another package (not main) puts it in the start state. chalk's loader refuses it; the deparser need not |
| 8 y probes | 1263 in chalk's set as y<name> (SAME 745, REFUSED 502, LOUD 16, WRONG 0), 86 WRONG (N1-N5, N7, N10, N11, N12, ya57) and 24 verifier-dirty y/unverified left out, listed in BASELINE.tsv comments |
| N8 rest | `local` under a condition and `delete local` refused by name; an operand before `local` of its variable is the old scalar (not read again) |

**Lessons:**

- **A rule for one consumer belongs on the wire, not in a skipped graph.**
  The start-up refusal first deleted main::__PROGRAM__; the deparser's
  module round trips broke, because the deparser's output `use`s the modules
  and perl runs them. A wire field (`start_up`) lets the consumer that runs
  the program from the wire refuse, and the one that does not, not.
- **"Relevant" must be what the program reaches, not what is on the wire.**
  Every followed module sub is translated; asking `_graph_modules` made
  `use Scalar::Util` relevant (export_fail is on the wire) and lost four
  gated SAMEs. Walk calls from the program and its BEGIN blocks.
- **A hand-built fixture written for v1 is no wire.** Five chalk tests
  round-tripped graphs with stores and no memory; the exemption hid it.
  Threading them took a set_control_in/set_mem_in/set_mem_out each, and one
  oracle had to count mem_in as a use-def edge.
- **Never `git stash` in a worktree.** Run once by mistake in a3-c; popped
  at once (worktrees share one stash: [[worktrees-share-one-stash]]).
- **"Code beyond plain data" is state CHECK cannot read, not any op.**
  `$Test::Builder::Level = 1 unless defined ...` is code and plain data:
  refusing every non-`our` op refused `use Test::Chalk`. Name what loses
  state (a lexical, a reference, a call, an object), not what computes.
- **A verifier-dirty probe cannot join a set the verifier holds.** chalk's
  wire-verify.t verifies every audit probe; 24 y/unverified probes stayed
  out, listed, rather than held by name.
- **`rm` is guarded here; a killed gate run leaves its wire cache.** gates2's
  ratchet read v1-looking wires a killed run left; start a new DIR, move old
  ones aside.
- **The verifier is a second net, not the first.** V13 catches 4 of the 6
  list-assign drops with the producer rule off (not `our` targets, not
  alias-list items): the refusal at the sink is what holds.

Related: [[the-third-final-audit-s-wrong-answers]],
[[the-second-final-audit-s-wrong-answers-lowered-or-refused]],
[[a-silent-drop-is-worse-than-a-refusal]].
