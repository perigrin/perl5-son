---
name: the-re-audit-s-wrong-answers-refused
description: "Branch reaudit-refuse: the 2026-11-23 re-audit's 68 silent wrong answers (classes A-G) and 3 invented errors refused by name, none lowered; a refused program sub rides the wire's `refused`; a try's eval shares its entry; a fixed-arity table pops someone else's operand; a new probe set joins the ratchet"
metadata:
  type: project
---

Branch `reaudit-refuse` (2026-11-23/24; producer 64a110f..1f402b9, chalk
41654fd8..890c0ff8; baseline section 21). The re-audit
(docs/research/2026-11-23-memory-model-goal-re-audit.md) found 68 WRONG in
499 probes (probes/r, chalk `re<name>`), all on wires SoN::Verify passes.
Every one is now REFUSED by name; none was lowered (A and B wait on a design
the user holds). re: SAME 339, REFUSED 156, LOUD 4 (runtime refusals), WRONG 0.

| class | where | refusal |
|---|---|---|
| A hash copy shares the source's node (26) | B::SoN aassign | `a copy of a hash that may then be written` -- either side in $MUTATED_SLOTS or %$HASH_WRITTEN (slice store/delete, call arg, foreach/values alias, undef), shared, or a package target |
| B fault under `local`, no eval (16) | chalk WireCheck W6 | `a Divide/Modulo/PostfixDeref that may die under a local` -- the walk now starts at a node that faults itself, not only a call |
| C finally/defer (6) | %UNBUILT_OP_GAP pushdefer | `a defer or finally block` |
| D bare `state` (3) | _refuse_bare_state | outside the program's straight line |
| E foreach over a written scalar (4) | enteriter | lvalue use of it; for a package/referenced/shared one any call or `$$r` store |
| F grep writes `$_`, read as a list (4) | grepstart | ModSets::_stores on `$_`, or a call whose callees may store an argument (EffectTable for XS) |
| G alias by another name (9) | _reread_alias_operand_stored_later | a `++$x` operand; a store through a reference; `$a[0]` vs `$r->[0]` |

Invented errors: C->get (`//=` into a package scalar, refused) is now in the
wire's `refused`, so chalk says why instead of "Can't locate object method";
nested try (red08) refused in T2 (two evals at one entry). aue1/rn1: rand,
srand, mkdir pop what the op says, now T2 refusals by name.

**Lessons:**

- **A refusal printed is not a refusal on the wire.** B::SoN said the
  program's refused subs on stderr only; chalk, finding no `get` in C, did
  what perl does for a missing method and died -- an error perl never gives.
  Everything refused must be on the wire for the consumer to tell "dropped"
  from "absent".
- **A map keyed by a node assumes one value per node.** `eval_at` keyed by
  eval_entry; a try makes no node where it begins, so a nested try shared its
  entry and one eval vanished -- even nested tries that never die printed
  nothing. Check uniqueness where you key.
- **A fixed-arity table entry is a silent wrong before it is a crash.**
  `rand()` underflowed (the lucky case); `5 + rand()` took the 5 as rand's
  operand. The sixth such operator; the rule is OPf_KIDS or the op's private.
- **B makes a PMOP a BINOP.** A match's OPf_STACKED is its `=~` target, not
  an op-assign; ModSets read every `$_[1] =~ /x/` as a store to the argument.
- **A new refusal costs probes: run the old ones.** The grep rule turned lw40
  SAME -> REFUSED (`my @g = grep {...}`, @g never read); narrowed to "the
  result is read". Two re probes went SAME -> REFUSED and stay so (rec02/03:
  a deref may die, the wire cannot say when).
- **A probe set in docs/research joins the ratchet.** probes/r made
  t/wire-verify-ratchet.t fail at 087e828 (r/a12: `sub z { @a = () }`
  returned the stored literal, at no version). Held first (216d190,
  8f6e3670); the coordinator said holds must shrink, not grow -- and it was
  a bug: the list assign's value is now @a at its store's version (1f402b9)
  and T2 returns a package array (890c0ff8, it refused `sub z { @a }` too).
  Fix before holding; a hold is for a design question.
- **Bonus not done:** SoN::Verify cannot see class A -- the wire names only
  the source's symbol on the literal; a mechanical check needs the copy's
  name on the wire (a format change).
