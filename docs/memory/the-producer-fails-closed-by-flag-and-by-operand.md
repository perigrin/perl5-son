---
name: the-producer-fails-closed-by-flag-and-by-operand
description: "Fifth audit, branch fail-closed: an op flag no handler reads is a GAP (one check in _step: TARGMY and a local's LVAL_INTRO by what the handler did, the rest by table); the operand rule's default is the refusal (EffectTable::pushes_new_value says what is a copy); Q1-Q6, Q8, Q10-Q12, Q14, Q15, Q18 SAME or REFUSED by name"
metadata:
  type: project
---

Branch `fail-closed` (2026-11-27), producer from 056d8482, chalk a2fe984d.
Audit: docs/research/2026-11-27-memory-model-final-audit-5.md, sections 4-5.

**The defect, in one sentence.** Each earlier fix listed the shapes it
handled, so the shape next to it fell through to "do what it did before":
the default was the silent answer.

**What fails closed now.**
- `_step` checks every op's flags before its handler: `%FLAG_READERS`
  (OPpDEREF, OPpLVAL_DEFER, OPpMAYBE_LVSUB: the ops whose handler reads it),
  and two by effect: an OPpTARGET_MY op must have defined its targ
  (`StackSim::defined_count`, not the binding's address: hash-consing gives
  `$x = $x++ + 1` the same Add twice) or moved memory; a `local`'s
  OPpLVAL_INTRO must have pushed a `local_saves` entry. `stringify` with
  TARGMY is lowered (`_store_into_targ`); `local ${"x"}`, `local $$n`,
  `local @{"a"}`, `local *{"x"}` are refused.
- The operand rule (`_alias_passed_through`) ends in `_refuse_unread_sv`:
  an operand no note covers is refused where a later operand may store it,
  unless `B::SoN::EffectTable::pushes_new_value` says the op pushes a value
  of its own. && || // re-read either operand; a one-statement `do`'s list
  and a list assignment's value are multi-notes re-read item by item; a
  `do` of statements, a call's argument list, a foreach/map/grep list and a
  map body are checked by `_refuse_list_stored_later`.
- Arguments perl hands on that the call cannot pass as places (lvalue
  substr, `$#a`, `$1`, list reverse) are refused where the call or a later
  argument may store (`_refuse_args_handed_on`). `++$x` as an argument is
  `$x`'s place.
- Q10: an array index names an element only as a non-negative integer
  literal, a hash key only as a string; AliasProof by `const_type`, V14 by
  stamp. vt59: a promoted parameter record needs a sub that stores nothing
  (the pass: `writes`; V14: `$stores_nothing`). M38-M44, each proof tested
  alone (the pass asks V14 too: stub `private_checker` to test the pass).
- Q11 stores a demoted range iterator's op= and ++; Q12, Q14, Q15, Q18 and
  `$1` after s/// (`$SUBST_MATCH`) are refused by name.

**Lessons.**
- A check "the handler changed the binding" is fooled by hash-consing:
  count the defines.
- `split` carries LVAL_INTRO for `my @a = split` (OPpSPLIT_LEX): a `my`,
  not a `local` -- 22 SAME probes went REFUSED for one run.
- `_alias_result_target` took a list assign for an op= (BINOP + STACKED) and
  overwrote its note: read what the existing notes say before adding one.
- The deparser renders a pre-store read of a `my` after a later store
  (`f(--$x, $x--)`) though the wire is right: check with chalk too.
- A test helper that greps `^GAP` misses `B::SoN: skipped ...: GAP:`.
