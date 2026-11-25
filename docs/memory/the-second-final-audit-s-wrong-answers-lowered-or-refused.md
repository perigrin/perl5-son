---
name: the-second-final-audit-s-wrong-answers-lowered-or-refused
description: "Branch audit2: the second final audit's 57 silent wrong answers -- K1 K4(part) K6 K8 K9 lowered, K2 K3(part) K4(part) K5 K7 refused by name; @_ copies read at a version, a followed module's start state is a BEGIN block, V12's alias-list half, V10 closed locals, the as_v1 mark, a pre-scan/walk agreement sweep; each new refusal first reached past its class"
metadata:
  type: project
---

Branch `audit2` (2026-11-25; baseline section 27). The second final audit
(docs/research/2026-11-25-memory-model-final-audit-2.md) found 57 WRONG in
828 probes (probes/z). Now in chalk's t/data/audit-probes as z<name> (826 +
pa79, un75): WRONG 0. GATES_LINE

| class | outcome | how |
|---|---|---|
| K1 (13) | SAME | `my ($p) = @_` binds each target to `$_[i]` read at a version; `my @l = @_` always a pinned copy; `my ($p, @r) = @_` placed. Verifier: a record is used where its target is |
| K2 (5) | REFUSED | `a variable handed to a sub as its $_[N] where that sub localizes it` (ModSets::arg_localized_by_call; an unknown callee only where scanned code localizes it) |
| K3 (5) | 2 SAME, 3 REFUSED | lexical iterator over one array: aliased by reference when a call's MOD set may store the list; `$_`/map/grep/package iterator, and a list of several items or one a call returns, refused by name. V12's alias-list half |
| K4 (8) | 3 SAME, 5 REFUSED | the op= refusal no longer needs OPf_MOD (a TARGMY add); `x=` of a list; an assignment as an alias-list item; a TARGMY op (`$x .= "b"` multiconcat) passed to a sub is its variable's place |
| K5 (6) | REFUSED | `an assignment's element is read by alias and a later operand stores into its container` |
| K6 (2) | SAME | chalk arg_alias: a package scalar read at a version older than its call's is a value; producer: a postincrement's value is no place |
| K7 (3) | REFUSED | `an aggregate flattened into a list is read by alias and a later item may store into its elements` (a reshape or a new hash key is no such store) |
| K8 (4) | SAME | store_at_write skipped any loop Phi as the iterator's own; `$y`'s Phi is a value to store (%LOOP_PHI_KEY) |
| K9 (11) | SAME | B::SoN reads a followed module's package scalars at CHECK and puts them first on the wire as a BEGIN block; aggregates, references, a program BEGIN that writes or calls: refused |

**Lessons:**

- **The audit's side of a class is a hypothesis.** K8 was reported as a
  pre-scan miss; both the scan and the walk said "written". The loss was
  one guard later: a store skipped for "its own loop Phi", which was another
  variable's. Read the wire and the code path, not the label.
- **Every new refusal first reached past its class, again.** K2 refused
  seven SAME probes (every code-value call: "an unknown call may localize");
  K7 six (a push, a new key, is no store into a flattened element); K3 one
  (the iterator read before the call). The sweep found each; each rule was
  narrowed to what changes the answer.
- **A module's main line is not in the optree.** perl frees a used file's
  code after running it at compile time; its effect is only in the stashes
  at CHECK. A start state read there is the program's.
- **`pgrep -f` matches the waiting loop's own command line**, so `until !
  pgrep -f X` never ends; wait on an output file instead.
- **A test run on a tree being edited reads both versions.** Sweep and
  prove from a snapshot (scratchpad/a2/sweep.sh).

Design question left open: K2 -- a place is the variable's storage, so under
`local` it names the new scalar. HHVM's box is the scalar. Either `local`
on the wire makes a new place (the save is the old place, the name rebinds)
and a place taken before keeps the old one, or the refusal stands.

Related: [[the-second-final-audit-s-wrong-answers]], [[aliases-are-places]],
[[a-sub-is-walked-once]], [[the-final-audit-s-wrong-answers-lowered-or-refused]].
