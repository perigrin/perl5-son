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

## CORRECTION (2026-08-28): three claims above are wrong

Superseded by discussion with perigrin against the formal types paper. The
MEASUREMENTS above stand; the INTERPRETATION of what the remainder means does
not. Left in place rather than edited, because chalk cites this document.

### What is wrong

1. **"58 of 100 are bucket one"** (line 68) and **"the producer genuinely does
   not know"** (line 75). Both false. Nothing in the 43 affected corpus cases is
   un-typeable. They are missing ANALYSIS, not missing evidence.
2. **`Unknown` treated as an honest, correct answer.** It is not. **`Unknown` at
   T1 is a FAILURE.** A well-formed program has none after inference converges.
   The DO-NOT-FIX list's reasoning inherits this error even where its
   conclusions happen to hold.
3. **The `:param` field question was answered on the wrong axis.** See below.

### The axis this document was missing

- **T1** ensures the program is WELL FORMED: every type as narrow as provable.
  Target-INDEPENDENT. **B::SoN does T1 only.**
- **T2** ensures every T1 type is REPRESENTABLE in the target's type system.
  Target-DEPENDENT, so it belongs to the consumer, not the producer.

`meet` returning `None` at T1 is a SITE, not a verdict: the two ends cannot be
satisfied by one type, so a coercion node is inserted there, acting as a type
guard for T2. **For now that insertion is unconditional.** Whether some pairs
(`ArrayRef -> Num` numifies to an address, which is rarely intended) should
instead warn or refuse is a POLICY question, deliberately deferred, and it
belongs to chalk.

Note the practical consequence: `meet(Undef, Num) = None`, so `my $x; $x + 1`
inserts a node. That is correct and it is COMMON -- expect the count to rise
well beyond the exotic cases.

### What actually blocks the remaining 100

Not un-typeability. Two missing passes:

**No backward inference.** Every pass in this document runs FORWARD, operands to
result. `_stamp_derived`'s arithmetic rule literally refuses when an operand is
`Unknown`. But a use site CONSTRAINS its operands:

    sub add1 { my ($x) = @_; return $x + 1 }

`+` imposes numeric context, so `$x : Num` -- from the body alone, with no
callsite. `meet(Scalar, Num) = Num`: the declaration's scalar slot meets the
operator's requirement. The signature `Num -> Num` follows. `Num` and not `Int`
because `add1(0.5)` is legal and nothing in the body excludes it.

The design is two facts per value node -- `lower` (join of definitions, rises)
and `upper` (meet of uses, falls) -- run to a COMBINED fixpoint. Separate fields
so each pass is monotone in its own direction; a single field with a combined
rule oscillates.

**Nothing narrows.** Measured on chalk: `TypeLibrary::meet_types` has ZERO
callers. So does `TypeLibrary::narrow_type`. `_narrow_unknown_coercions` is
wired but is not narrowing -- it back-patches a `Coerce`'s stale `from_repr`
from an independently-inferred operand. Three uses of the word "narrow", none of
them narrowing. Chalk's inference is join-only end to end.

### Measured, and it supports the paper's claim

**188 of 231 corpus cases are FULLY typed** -- zero `Unknown` anywhere. Of the 43
that are not, none involves `tie`, `local`, symbolic refs, or string `eval`. The
groups are argument binding (F3/F5/F6/F7/F8/F14/F15/F16), `:param` fields, and
store-then-read -- all analysis gaps.

Also measured: **868 values carry a use-site requirement and every one has
exactly ONE distinct requirement; zero conflicts.** Not a corpus accident -- the
producer already inserts a coercion at each context boundary, so a value's second
context is consumed by the `Coerce`, never by the value. Per-node `upper` is
therefore sound, CONDITIONAL on the pass running after coercion materialization.
Move materialization to T2 and per-edge `upper` returns.

### Why `Coerce[Scalar->Str] is not lowered` proves nothing about the lattice

Quoted at `FromOptree.pm:104` as evidence that `Scalar` is the wrong stamp. It
is not. It is a BACKEND gap: `_emit_to_str` dispatches on representation and has
arms for `Str`/`Boolean`/`Num`/`Int` because those have distinct carriers.
`Scalar` has no arm because `Scalar` names no representation -- it is a T1
element with no T2 image. The failure is a T1 value reaching a T2-dispatching
backend un-narrowed, which is exactly what happens when nothing narrows.

Correspondingly, `meet(Int, Str) = Int`: on the TYPE axis an `Int` already
satisfies a `Str` requirement, so the stringification coercions the producer
inserts today are invisible to a type-axis meet. They are T2 conversions
(`i64` to `(ptr,len)` via snprintf) and belong to the repr axis.

### Consequence for the wire contract

Under "B::SoN does T1 only", the producer should not emit `Coerce` nodes at all:
`_coerce_to_str` and `_coerce_int_to_num` are T2 decisions made by a layer that
does not own the target. Most of T2 already exists on chalk's side --
`TypeLibrary::operand_repr_for_ir_op` publishes per-op, per-position repr
requirements, and `_emit_coercion`'s nine arms are the repr lattice's edges.
What is missing is the pass that meets them.

**This is a wire-contract change and is NOT scheduled.** Recorded here so the
audit's conclusions are not read as a ceiling.

## WHY `Unknown` AT T1 IS A FAILURE (the argument, not just the claim)

The correction above asserts this. Here is why it holds, because it was pushed
back on and the pushback lost. Measured against the lattice in
`SoN::IR::Stamp`, not argued from principle.

**The objection.** In abstract interpretation (Cousot 1977) top is a legitimate
TERMINATING result -- the lattice has a top precisely so analysis can stop on
values it cannot narrow. Graal, which `Value.pm` cites, carries an unrestricted
stamp and lowers it. Rice's theorem says no sound terminating always-non-top
analysis exists over a Turing-complete language. So "no `Unknown`" looks like a
claim about the ANALYSIS (completeness) smuggled in as a claim about the
PROGRAM (well-formedness).

**Why it fails here.** That objection needs a REACHABLE top. This lattice has
none, for two independent reasons:

1. **`meet` never reaches top.** Measured over every expressible pair: 0 return
   `Unknown`. It bottoms at `None` (122 pairs), which is a COERCION SITE by
   design, not a failure.
2. **`join` reaches top only via `Code`/`Glob`/`IO`/`Format`** -- 42 pairs, and
   every one involves those four. Nothing else can get there, because everything
   a Perl scalar can hold sits under `Scalar`, and every scalar-ish pair joins
   informatively: `join(Int, ArrayRef) = Scalar`, `join(Object, Int) = Scalar`,
   `join(Array, Hash) = List`.

**And those 42 are unreachable IN THE GRAPH** (see the `eval` correction below --
`Code` is producible in Perl, but the construct producing it is refused). `join(Code, List)` needs one value that is a
bare `Code` on one path and a `List` on another. A Perl scalar holds a
`CodeRef`, never a bare `Code`; bare `Code` is a glob's code slot (`*foo{CODE}`)
and does not flow through a scalar without becoming a ref. No expression yields
such a value.

**`Scalar` and `List` are the real tops.** Not `Unknown` -- the formal top is
correct and simply never inhabited by an expressible value. `Scalar` is
INFORMATIVE: it excludes `Array`, `Hash`, `Code`, `Glob`. Terminating at
`Scalar` is a sound answer, not a failure, so the analysis never NEEDS top to
terminate. That is what defeats the Rice's-theorem framing: undecidability does
not disappear, it is absorbed by an imprecise answer still being a useful one.

**So two readings must be kept apart:**

- `Unknown` as a COMPUTED JOIN -- `lub(Code, List)`. Correct, and unreachable.
- `Unknown` as a STAMP ON A NODE -- nobody ran an analysis. **This is the
  failure, and it is all 100 on the wire.**

**A trap recorded on the way:** `Code`/`Glob`/`IO`/`Format` are parented at
`Unknown` because their join with anything scalar-ish genuinely HAS no better
answer. Reparenting them under `List` drives the 42 to 0 -- and would be
manufacturing a subtype relation to make a number go to zero, the same
"invent an answer to close an Unknown" error as the R10 miscompile one level up.
(Whether `Glob <: List` is semantically true -- a glob does hold plural slots --
is a real question, to be decided on what a glob IS, not on this.)

**CORRECTION: `eval` IS `String -> Code`, and bare `Code` IS producible.**

An earlier draft of this section claimed `eval` does not produce bare `Code`,
on the evidence that `eval "sub { 42 }"` returns a `CodeRef`. That answered the
wrong question -- it sampled what the eval'd code RETURNS, not what `eval`
itself denotes.

`eval STRING` compiles a string into CODE and applies it. The type is
`String -> Code`, applied immediately -- the `Code` is CONSTRUCTED AND RUN IN ONE STEP, never
bound to a variable, never escaping. `eval "1 + 2"`
being `Int` and `eval "say 'hello'"` being say's result are properties of the
APPLICATION, not of `eval`. So bare `Code` is a value Perl can produce, and the
"unproducible" claim below was false as stated about Perl.

**Ephemerality is the deeper reason, independent of the refusal.** A value that
is constructed and applied in one step never reaches a MERGE. It cannot be
stored, cannot flow to a Phi, cannot meet another value on a branch path. So
`join(Code, List)` is unreachable for this construct not because `Code` is
unproduced, but because an immediately-applied value has no join partner. Top
needs two values arriving at one point; `eval`'s `Code` is never one of two.

**The conclusion survives on different grounds: `entereval` is REFUSED.**
`FromOptree.pm` GAPs it, and the reason is exactly this one -- "the entereval op
is present but the eval'd code is not, because perl compiles that string only
when the op EXECUTES". B::SoN walks at CHECK time; the `Code` does not exist
yet. The GAP is permanent by design, not a TODO, and it holds even for a
constant operand, since building it would mean invoking the perl compiler
mid-walk.

So the `Code` never enters the IR, never gets a stamp, never joins. Top stays
unreachable IN THE GRAPH -- not because bare `Code` is unproducible in Perl, but
because the one construct producing it is rejected before any node exists.

Note this makes the property CONTINGENT rather than structural: if `entereval`
were ever lowered, bare `Code` would enter the lattice and
`join(Code, List) = Unknown` would become reachable.

**THREE FATES, and only the third is a failure:**

1. **Refused** -- `entereval`, `goto`, `write`. A GAP. The honest answer for a
   construct that violates the type system.
2. **Typed** -- everything expressible, bottoming at `Scalar` or `List`, both
   informative.
3. **Stamped `Unknown`** -- nobody ran an analysis. The failure.

Implementing the exception clause as refusal rather than as top is the stronger
position: a type-system violator is rejected, not assigned an uninformative type
and passed downstream.

## RETRACTED: `List` MEANS PLURAL, NOT EPHEMERAL

The section below is WRONG and is kept only because it is already pushed.
perigrin: "We moved Scalar under List ... and it's Durable."

`Scalar => [qw(List)]` was in the lattice the whole time. `Scalar` is a child of
`List` and is obviously durable -- as are `Array` and `Hash`, the other two
children. So `List` CANNOT mean "exists only in transit"; its most important
child is the ordinary durable scalar. The counterexample was three lines above
the entries being read.

**`List` means PLURAL.** It is what values flatten into and out of. `Scalar` is
the singleton case; `Array` and `Hash` are the stored cases. **Durability is an
ORTHOGONAL axis**, not what the lattice edge encodes.

Consequences:

- **`Glob <: List` is right**, on plurality grounds: a glob holds five typed
  slots (`*x{SCALAR}`, `{ARRAY}`, `{HASH}`, `{CODE}`, `{IO}` -- verified, all
  populated at once). It is durable, and `Scalar` already proves durable-under-
  `List` is fine. The objection raised below -- that a glob survives binding and
  so cannot be under `List` -- was an artefact of the wrong reading.
- **The "ephemeral tier" is not a tier.** `List`, `Code`, `Glob`, `IO`, `Format`
  share a PARENT, not a property.
- **Top-unreachability still holds**, but on the earlier grounds: `join(Code,
  List) = Unknown` is the correct lub of two things that no expression brings to
  one merge point. That argument does not need the ephemeral framing.

Also measured while testing this, and it corrects a second claim below:

- **A glob is NOT coerced in scalar or IO context.** `my $g = *x` stays a
  `B::GV`; `print {$h}` leaves it a `B::GV`; stringifying leaves it a `B::GV`.
  No conversion happens at all.
- **`*STDOUT{IO}` is not a coerced glob** -- it is the IO SLOT selected out of
  the glob, and it was always a blessed `IO::File`. `{IO}` indexes the glob the
  way `{ARRAY}` does. That is selection, not coercion.
- So **`IO <: Object` needs care**: what you get from `*STDOUT{IO}` is a REF to
  the IO slot (`Object <: Ref <: Scalar`, durable). Bare `IO` -- the slot's own
  type -- is glob-slot-shaped like bare `Code`, whose ref is `CodeRef`. Whether
  the lattice's `IO` node names the slot or the handle-you-hold is a naming
  question about the model, and it decides whether `IO` moves under `Object` or
  stays a peer of `Code`.

## THE EPHEMERAL TIER -- why `Unknown` is the top, and why that is correct

perigrin: "Ephemeral just like a bare List!" That is the structural account,
and it supersedes both the "unproducible" claim and the contingent
`entereval`-is-refused one.

**The five types parented at `Unknown` are exactly the values that exist only
in transit**: `List`, `Code`, `Glob`, `IO`, `Format`. None can be bound to a
variable.

- A bare `List` -- `(1,2,3)` -- flattens into an assignment target, a sub's
  arguments, a return. Store it and it becomes an `Array`; take one and it is a
  `Scalar`. It is never held AS a list.
- `eval STRING`'s `Code` is constructed and applied in one step.
- `Glob`, `IO`, `Format` are symbol-table slots, not values a scalar holds.

**Measured, and the lattice already encodes it exactly**: every ephemeral member
joins to `Unknown` with EVERYTHING -- with each other AND with every durable
type. All 42 top-reaching pairs involve one, and no ephemeral pair joins below
top.

**So top is unreachable BY CONSTRUCTION.** A join needs two values arriving at
one program point, which needs both to persist to that point. Nothing ephemeral
does. `Unknown` is therefore the join of things that cannot join -- correct, and
never inhabited.

This does not depend on the corpus, and it does not depend on `entereval` being
refused. It is a property of what the types ARE.

**The internal asymmetry that explains `CodeRef` vs `Code`:** `List` is the only
ephemeral member with DURABLE children (`Array`, `Hash`, `Scalar`, `Void`) --
storing a list is what gives you an array. `Code`/`Glob`/`IO`/`Format` have no
durable form at all; you can only take a REFERENCE, which lands at
`CodeRef`/`GlobRef` under `Ref <: Scalar`. A different thing. That is why
`CodeRef` joins informatively and bare `Code` does not.

**And it retires the reparenting idea for good.** `Code <: List` would claim a
subtype relation WITHIN the ephemeral tier -- one transient thing a kind of
another -- when they are peers. Driving 42 to 0 that way would have been the
symptom of a false claim, not the reward for a true one.

**Still independently true:** an `Unknown` reaching **T2** is fatal for its own
reason -- top has no REPRESENTATION. That is `_require_repr`'s question and does
not depend on any of the above.

## New tests

    t/wire-call-return-stamp.t        callee return type reaches the callsite
    t/wire-field-access-stamp.t       field reads take the declared field type
    t/wire-subscript-element-stamp.t  element types, membership, store invalidation
    t/wire-phi-join-stamp.t           merge and logical-op joins
    t/wire-selftyped-stamp.t          Not/Ref/qr// and arithmetic
    t/wire-assign-stamp.t             an assignment yields what it stored
