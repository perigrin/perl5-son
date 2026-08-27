# Wire-`Unknown` audit: result

**Date:** 2026-08-27
**Repo:** perl5-son (producer), branch `pu`, commits `bf2b039..f2d5637`
**Brief:** chalk `docs/plans/2026-08-27-wire-unknown-audit-brief.md` (plan section 5.0b)
**Measured over:** chalk's 231-case mdtest corpus, identical population before and after

## The claim, and the verdict

> 233 `Unknown` stamps on the wire is a frontend defect, not a fact of life.
> B::SoN walks a real optree with real SV types in hand. An `Unknown` on the
> wire is the producer declining to answer a question it was holding the
> evidence for.

**The claim held, by a wide margin.** The brief said explicitly that if most of
the 233 landed in "the optree genuinely cannot know", the premise was wrong and
that was the finding. It did not.

| bucket | count | share |
|---|---|---|
| one -- optree genuinely cannot know | ~15 | ~6% |
| two -- optree knows, producer never asked | ~200 | ~86% |
| three -- asked, then dropped | 0 confirmed | -- |

Two structural findings mattered more than the headline:

1. **87 of 233 (37%) were pure CASCADES** -- an `Unknown` fully explained by an
   `Unknown` input. The corpus never had 233 independent decisions; it had
   **146 roots**. Fixing a root collapses its cascade for free.
2. **ZERO runtime-polymorphic dispatch in the entire corpus** -- no
   `$obj->$name()`, no `eval "$str"`. Every `Call` resolved statically. That was
   the premise's biggest risk and it did not materialise.

The sharpest single instance: `return_type: "Int"` sat on the sub's metadata
record while the `Call` node **in the same JSON document** read `stamp:
"Unknown"`. The producer computed the answer and discarded it at the last step.

## Result

**Wire `Unknown`: 233 -> 100**, same 231 cases.

| commit | change | count |
|---|---|---|
| `bf2b039` | Call takes callee return type; FieldAccess takes field type | 233 -> 195 |
| `7cc1c11` | Subscript of an unwritten literal reads its element type | 195 -> 171 |
| `7967639` | Phi / `&&` / `\|\|` / `//` stamped with the join of their arms | 171 -> 140 |
| `364a631` | a read that is not there is `Undef`; three self-typed stamps | 140 -> 125 |
| `f2d5637` | an assignment takes the value it stored | 125 -> 100 |

By op: Call 60->37, Subscript 44->18, Phi 35->10, Assign 28->3, FieldAccess
21->6, Add 18->9; DefinedOr, Constant, Not and Ref to zero.

## Why the remaining 100 is the right place to stop

The cause split has inverted. Re-measured on the remainder:

| count | cause |
|---|---|
| 29 | cascade -- root is one of the below |
| 28 | callee return itself `Unknown` (bottoms out at `shift`) |
| 16 | `:param` field or list-assigned param, no declared type |
| 7 | builtin result (`shift`/`exit`) |
| 7 | **memory Phi** -- merges `MemStart` with a store, not values |
| 6 | **subscript after a store** -- deliberate soundness guard |
| 5 | aggregate not a literal (field-backed / `@_` / nested) |
| 2 | logical arm is a `Print` (control node, no value) |

58 of 100 are bucket one, 29 are cascades off them, 6 are the guard that
prevents a miscompile, and 7 are memory Phis.

Two that looked closable and are not:

- **A `:param` field with no default has no `type` on the wire at all** -- not
  `Unknown`, *absent*. Its type depends on what a caller passes at construction.
  The producer genuinely does not know.
- **Memory Phis** merge memory states, and `MemStart` carries no stamp. Stamping
  one from the store's value type would assert that a memory state is an `Int`.
  Wrong, and it would reach chalk's merge sites.

Both are the `Array[Scalar]` element-type wall in different clothes -- the same
wall behind the 28 callee-return cases. It was already documented in this
repo at `FromOptree.pm:4771` before this work started.

## The miscompile, and the lesson

`7cc1c11` shipped a wrong program. Chalk's behavioural gate caught it
(`references.md` R10, gate 215 -> 214):

    my %h = (a => 1, b => 2);
    say($h{z});          # perl: empty line.  chalk after 7cc1c11: 0

The pass stamped that read `Int`, which deleted the `Coerce` that renders undef
as the empty string, so the payload printed as `0`.

**The rule was already written down, in that same commit's own comment:**

> out of range yields undef, so a constant index is bounds-checked and a
> computed one stays Unknown

Applied to array indices, never written for hash keys. A missing key *is* an
out-of-range index -- the read yields undef, so no element type describes it.
The value join was not the wrong part (`Int` really is `join(1,2)`); it simply
did not apply, because the key was not there.

Fixed in `364a631` as **one rule over both container kinds**: the key must be a
literal AND a member of the literal's key set; the index must be a literal AND
in range. Absent either, `Unknown`. A provably-absent read is stamped `Undef` --
a real lattice member, statically known, and it survives chalk's loader (which
writes `Unknown` as an absence). `Slot` would have been wrong: that is a target
ENCODING, not a lattice member, and `join(Slot, Int)` is `Unknown`.

Three subtests pin it, including the bilateral one -- **a present key must still
take the value type**, without which the fix is indistinguishable from disabling
hash stamping entirely.

**The lesson:** the guard was written for the shape there was a test for. The
post-store case was caught by reasoning; this one was not, and only the
behavioural leg could see it. This was the first producer change in nine gate
runs across three SHAs to move chalk's gate -- the pairing did its job.

## Discipline notes

- Every fix is TDD: failing test first, and **every negative/guard subtest
  passed BEFORE its fix and still passes**, so no blanket stamp could have
  satisfied any of them.
- Every pass **only propagates, never invents**. An undetermined callee, an
  untyped RHS, a field with no default, a computed index -- all stay `Unknown`.
- The passes run as an ordered chain in `_discover_and_translate`, because a
  single-CV walk cannot answer these: a `Call` is built while translating its
  CALLER, and for a recursive call no order helps. The order is a dependency
  chain, not a preference:

      field type -> FieldAccess -> method return type -> Call -> subscripts -> merges -> derived

  Method return types are RE-derived mid-chain; without that, `method val {
  return $n }` reports `Unknown` and every callsite reading it learns nothing.
  That is why closing FieldAccess 21->6 also bought Call 60->37.
- The merge pass runs **to fixpoint across node kinds**, not within `Phi`. Found
  by writing a test against the wrong node: a correctly-poisoned `Phi` whose real
  root was an `Unknown` `DefinedOr` one level down.
- Verification on every commit: clean rebuild (`rm -rf blib`, `Makefile.PL`,
  `make`) then `prove -Ilib -Iblib/lib -j1`. Final: **120 files, 634 tests, all
  pass**. Chalk's corpus gate was never run from this session -- it resolves the
  producer as a live path with no version pin, so it was serialized through the
  chalk coordinator.

## Gate confirmation (chalk coordinator, `f2d5637`)

**215/215/215/215, 241/241, 0 failures.** Zero behavioural mismatches.

The 214 at `7967639` was the R10 miscompile, fixed in `364a631`. Gating
`364a631` then showed `gate-green=212 behavior=215 shape=212` -- three cases
red on the SHAPE leg only, with **zero** behavioural failures: arithmetic OOB
read, `references` R9 OOB read, and R10. Their hand-written ir blocks still
specified `Subscript :Slot` / `Coerce(Slot -> Str)`.

**Those specs were stale, not the stamps.** `Slot` is a target encoding; `Undef`
is the lattice member and the true static answer. Chalk updated six lines across
the three cases (chalk `3ebf0ce8`) and the gate returned to 215/215/215/215.

Two things worth carrying forward:

- **The shape leg compares spec against wire, so it goes red on a CORRECT
  producer change** whenever a hand-written ir block still encodes the old
  answer. Expect it to be the leg that moves first on any future stamp change --
  and check which leg moved before assuming a regression.
- **`Undef` survives chalk's loader today**; `Unknown` does not (its
  `%LOWERABLE_STAMP` writes `Unknown` as an absence -- chalk's section 5.0, not a
  producer defect). That is why a provably-absent read is stamped `Undef` rather
  than refused.

Nine gate runs across five producer SHAs; exactly one moved the gate, and the
behavioural leg caught it within minutes of landing.

### Do not "fix" the 7 memory Phis

Recorded because it would look like an easy win and is a wrong answer with a
plausible shape. They merge MEMORY STATES; `MemStart` carries no stamp. Stamping
one from its store's value type asserts that a memory state is an `Int`, and
chalk's join would then propagate that through its merge sites.

## New tests

    t/wire-call-return-stamp.t        callee return type reaches the callsite
    t/wire-field-access-stamp.t       field reads take the declared field type
    t/wire-subscript-element-stamp.t  element types, membership, store invalidation
    t/wire-phi-join-stamp.t           merge and logical-op joins
    t/wire-selftyped-stamp.t          Not/Ref/qr// and arithmetic
    t/wire-assign-stamp.t             an assignment yields what it stored
