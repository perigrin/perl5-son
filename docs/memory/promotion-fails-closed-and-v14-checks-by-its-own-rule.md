---
name: promotion-fails-closed-and-v14-checks-by-its-own-rule
description: "Audit 4 class X5 (branch x5-promote): SoN::AliasProof::conflict fails closed (captures count as references, `my|` spelled, table ends 'may conflict'); V14 is SoN::PromotedPrivate, a simpler rule sharing nothing with the pass (the pass asks it too); the probes gate also sweeps with SON_NO_PROMOTE=1; 16 X5 probes WRONG -> SAME"
metadata:
  type: project
---

Branch `x5-promote` (2026-11-27), producer from 9edd0dc5, chalk from 07111727.
Audit: docs/research/2026-11-26-memory-model-final-audit-4.md, section 4.2.

**The defect.** `sub f { $_[1]->(); $_[0] } my $x=1; print f($x, sub { $x=5 })`
printed 1 (perl 5): P1 promoted `$x` to the value read before the call.
`AliasProof::conflict` had three holes, each a "no" it could not prove:
`referenced` counted `Ref` nodes only (a capture is a `MakeCell` beside the
caller's `PadAccess`, no `Ref`); `kind` matched `my:` where `src` spells a
non-shared `my` `my|G|$x` (so `R:scalar` never reached one); and the table
ended `return 0`. Two more found by neighbours of the 16: `referenced` stored
`elem:...#0` keys but looked them up stripped (a `\$a[0]` never counted), and
a caller's own `$_[N]` handed on (`P`) conflicted only with `P`.

**The fix.**
- `conflict` lists the pairs that are different storage (two named
  variables, a named scalar beside an element of a named container, kinds
  that cannot meet) and ends `return 1`. Captures (`MakeCell cell_name`,
  `AnonSub captures`) count as references of the maker graph's `my`.
- V14 is `SoN::PromotedPrivate`: the callee is on the wire and only reads
  `@_`; the argument is a `my` of the caller no Ref/closure/shared sub
  reaches, or nothing on any way from the callee's start to its reads of
  `@_` may store it (QUIET: pinned reads, Ref, MakeCell, print, a store to a
  variable V14's own names say is another -- lexicals by symbol in any graph,
  elements by container and constant index --, a `local`, a push, calls of
  QUIET subs); a read before the call has nothing between that may store it.
  It asks nothing of AliasProof or the effect table. `SoN::Promote` asks it
  too, so V14 is hard and the pass never makes what it rejects.
- Mutation cases M27-M35 promote by hand and stub AliasProof to say
  "private": V14 still rejects each; M33-M35 were each seen to pass a V14
  mutated by hand (names always differ; any `local` makes a new scalar).
- tools/gates.sh probes phase also runs t/probes-with-promotion-off-are-not-wrong.t
  (chalk's sweep with SON_NO_PROMOTE=1): WRONG 0, TIMEOUT 0 both ways.
- chalk: the 16 probes are rows `xx<name>` in t/data/audit-probes (SAME).

**Lessons:**

- **A shared predicate cannot check itself; a mutation test must stub it.**
  The M19-M26 cases broke wires the shared proof already knew; stubbing
  AliasProof to "private" is what shows V14 is independent.
- **A key stored one way and looked up another is a silent "no".** `referenced`
  had that bug from the start; a table-wide `return 1` does not catch it.
- **The checker must live where the compiled program cannot replace it.**
  B::SoN compiles in the program's process: probe r/v `use lib`s another
  tree's SoN::Verify, and a `private_checker` in SoN::Verify was "undefined"
  for SoN::Promote (wire dropped). Hence its own module.
- **A stricter checker the pass also asks costs precision; the suite's
  "every argument is a value" cases measure it.** The first V14 (any store
  in the callee is a store) unpromoted `$a[1]=9`, `local $x=2` and `push @a`
  callees (t/wire-an-alias-not-proved-private-is-a-place.t 46/50/52); and
  AliasProof's new "may conflict" default first took a `my` scalar for a hash
  element (`$_[0]{m} //= {}`), which the deparser's round trip
  (t/deparse-a-foreach-alias-is-a-reference.t) showed: with that argument a
  place, the deparser prints nothing -- the same on the base with
  SON_NO_PROMOTE=1, so a deparser fault promotion hides (not fixed here).
- **Neighbours first.** Of eight one-shape-away programs, four more were
  promotion's (P handed on, `\$a[0]` of a package and a `my` array, a
  callee's copy of a reference); one, `for my $x (@a) { f($x) }` with f
  storing `$a[0]`, is WRONG with promotion off too (construction, not X5).
- **"The pass asks the verifier's rule" holds only if both see one wire.**
  combo2's ratchet (SON_RATCHET=1, chalk's lib -- not run on x5-promote)
  found 18 graphs V14 rejected, all `$self->m($self->n(...))`: the outer
  `$self` read where perl pushed it, before n(). The pass had already
  rewritten n()'s argument to a node the checker's map did not hold (read
  as nothing: harmless); V14 then saw it and took any input naming `$self`
  for a store (a false positive: it is a promoted value, a copy). Fixed on
  combo2-v14: the pass hands each node it makes to the checker (`$add`), and
  a call stores a caller's `my` only through a place it is handed to a
  callee that may store @_ (t15 clean, M37). All 18 were sound.
- **Run the ratchet with chalk's lib (SON_RATCHET=1) before calling a
  verifier change done.** Corpus and probes held 0; chalk's lib held 18.

Related: [[places-everywhere]], [[the-fourth-final-audit-s-wrong-answers]],
[[a-verifier-that-reads-a-derived-flag-checks-itself]].
