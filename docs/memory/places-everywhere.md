---
name: places-everywhere
description: "Branch places-everywhere (design B): every alias a place at construction, promotion a separate pass over the wire (SoN::Promote, proofs in SoN::AliasProof, V14 checks each promoted node); SV operands read when their consumer runs; local of a named scalar is a new scalar (chalk bind::NAME); audit 3 N1-N8, N10-N12 lowered or refused by name"
metadata:
  type: project
---

Branch `places-everywhere` (2026-11-25; design docs/plans/2026-11-25-places-everywhere.md,
section 10 "as built"). Producer from f06ba3e, chalk from eca706af.

**What changed.**
- Construction is naive: every argument perl aliases is a place
  (`$ARGS_ARE_PLACES` always 1); `my (...) = @_` reads each `$_[i]` at its
  version; an SV operand is read at its consumer's version after a store
  since it was pushed (`_note_alias_operand` / `_reread_alias_operand_stored_later`);
  an array item of a foreach/map/grep list is its place; an assignment as an
  item or a list-assign target is its target.
- `SoN::Promote` runs in `to_json` before encoding: P1 (an argument place ->
  the read where perl pushed it, or at the call, where no callee stores it
  before reading `@_`, none stores through `@_`) and P2 (a copy of `@_` ->
  the parameter record where no call hands the sub a place and no unseen
  code calls it). `SON_NO_PROMOTE=1` leaves the naive wire. Each promoted
  node is `fields.promoted`; `SoN::Verify` V14 re-proves it (M19-M26).
- `local $x` of a named package scalar: `EntryWrite local` (a new scalar),
  the save `Ref [EntryDef]`, the restore `EntryWrite binds`; chalk reads and
  stores such a name through `bind::NAME` (a cell pointer, undef = static).

**Lessons:**

- **A pass after the walk must keep the walk's typing.** P2's first form
  rewrote the reads to the record but the stamps typed from them stayed
  (`And` Scalar, a return List): census 425 for 426 (an LLI_FAIL). The
  copies are now read untyped, as a parameter is, and not floored.
- **A promoted value must be the read the walk would have made.** Read at
  the call's version, the deparser saw an element read "after a store in the
  same iteration" (a LocalAlias) and refused, and chalk passed `$a` of a
  sort block by alias. The walk leaves a hint (the version the variable was
  read at); the pass reads there where nothing between stores it, and reuses
  the walk's own node -- but only one made before the call (L8: "names X,
  made after it", 37 census GAPs).
- **A place made of a value's node names what the value was read from.**
  `my ($l) = @_; $l->m` handed `m` the caller's `$_[0]`: a `my` scalar kept
  in no memory has no place, only its value.
- **Version changes are not stores.** A pinned read is a memory version that
  stores nothing; re-reading after one made dead pinned reads (L4) and a
  pinned ternary the deparser had no rule for. Re-read only after a store.
- **Store sets are by what the wire says writes.** AliasProof's first cut
  took a builtin's every input as stored (`push @{$_[0]{s}}, $_[1]` "stored
  through @_"), a CellWrite as no store, a pinned read as a store: each a
  regression the census or the gated probes caught.
- **A cell alias must not cell a literal.** Making an element alias its cell
  (N2) stopped on a read-only literal list (`map { N->new($_) } qw(...)`):
  only a plain array is turned to cells; an alias array's own cell is passed.
- **A guard is spelled where it is used unless it is pinned.** The test
  "did the element exist where perl pushed it" made at the old version but
  unpinned floated: the deparser spelled `exists` after the call that made
  the element (`($r->[0], f())` printed 5 for undef). Made and pinned where
  pushed -- only where a later operand calls a sub, as the old plan did.
- **Untyped is for what the pass may rewrite, not for every `$_[N]`.** Leaving
  every ArgsSource read unfloored made an eval's Phi Unknown and the deparser
  refused it; only the `my (...) = @_` copies are left untyped (`%ARGS_COPY`).
- **grep returns the element, not the read.** With the call's argument a place,
  grep's appended element read at the loop head was spelled after the call:
  the kept element is read after the body where the body may store.
- **A refusal deleted with its machinery must come back by name.** The
  operand re-read rewrite dropped `_elem_alias_plan`; `print $r->[0], f()`
  with f shifting `@$r` printed 2 where perl's alias is to a freed scalar.
  The suite's own `like $reshape` tests caught it once read, not skimmed.
- **Two verifier rules on one fact must share its model.** V12's own store
  model said a callee's `local $x = 5` stores the caller's `$x`; AliasProof
  (V14) knows it binds a new scalar. V12 now leaves promoted arguments to V14.
  V12 still caught a real silent wrong: the topic `$_` read after `z()`
  stored its element (`do { z(); $_ }`, pa09).
- **A pass's stats need the unit of the old one.** The old fast path counted
  bindings; P1 first counted calls. Per argument, chalk's lib per file: 15.1%
  stay places, mostly calls of a sub in another file (the wire cannot see it).
- **@_ is not reference counted.** A callee's `@a = (7)`, `shift`, `pop`,
  `splice` or `$#a =` frees the element an alias holds (perl reads "" or
  panics); only `push`/`unshift` leave it. AliasProof keeps those as stores.
- **Perl's hash order is per process.** y/yp13 is order-dependent: perl gives
  8 or 9 run to run; chalk's 8 is one of perl's answers.

Related: [[aliases-are-places]], [[the-third-final-audit-s-wrong-answers]],
[[the-second-final-audit-s-wrong-answers-lowered-or-refused]].
