# `from_repr` is a cache T1 does not need

**Date:** 2026-09-04
**Status:** Measured, nothing changed. The fix is a wire decision, not a
producer-local one.
**Relates to:** `t/wire-coerce-from-repr-refresh.t` (the `local $TODO` this
note replaces the reasoning for)

## What the field is

`Coerce` carries `from_repr` alongside `to_repr`. The pair reads as a
declaration -- "this node converts A to B" -- and that reading is wrong.
Measured over `t/base/*.t` + `t/comp/*.t`, 376 Coerce nodes:

  - 375 of 376 non-`Unknown` values are **equal to `inputs[0]`'s stamp**.
  - The 1 exception is hardcoded and false (below).

So `from_repr` is a **cache of `inputs[0]->stamp`**, spelled like a
declaration. Two consequences follow from the naming alone:

1. **It reads as authored, so nothing refreshes it.** 210 of 376 claim
   `Unknown` over an input that inference later typed. `_coerce_to_str`
   samples the stamp at CONSTRUCTION time; its own comment says this
   "obliges a later pass to NARROW it before anything is lowered." That pass
   was never written.

2. **It is in `content_hash`, and `content_hash` IS the node id.** Identity
   should mean "what conversion is this." A derived cache in the id is why
   the refresh cannot be a mutation -- the node would sit in the intern
   table under a key that no longer matches it.

## The one false value

`t/comp/parser.t` has a Coerce whose input is not `Str`:

    Ref(ScalarRef) -> PostfixDeref($, Scalar) -> Coerce(from_repr=Str -> Regex)

`Scalar` is the honest stamp for a deref result; the referent's type is not
statically known. `from_repr => 'Str'` is hardcoded at
`lib/SoN/FromOptree.pm:3771` and will claim `Str` whatever flows in.

Everything else in that subgraph is correct -- the `Ref`/`PostfixDeref` pair
models the deref, and `to_repr => 'Regex'` correctly marks "compile this as a
pattern." **`from_repr` is the only part of the Coerce family that ever
states something false.**

## Why this is not a producer bug to fix with a producer pass

The T1 obligation is that the graph describes the perl program truthfully.
By that standard the defect is real and simply stated: **a node asserts
`Unknown` (or `Str`) about a value the graph knows the type of.** The graph
contradicts itself. That is wrong whether or not anything consumes it.

What the defect is NOT is a lowering problem. The original justification for
fixing it was that chalk's LLVM backend dispatches on `from_repr`
(`Int->Num` -> `sitofp`) and `Unknown` matches no arm. That is a T2 symptom,
and taking it as the specification produced two rounds of wrong work:

  - a fixpoint pass to keep the cache fresh (210 stale -> 57), which left
    BOTH the old and new Coerce nodes in the graph, because membership is by
    reachability and insertion does not remove;
  - a design for a Graph-level node REPLACEMENT operation to make that pass
    possible.

Both were infrastructure built to serve a field that should not be read.
`t/cmd/elsif.t` failing as "Coerce[Scalar->Str] is not lowered" is likewise a
T2 report; it is recorded in the `_coerce_to_str` comment as though it were a
T1 requirement.

**This repo stops at T1.** If a decision here turns on what LLVM type
something becomes, the layers have been mixed and the reasoning is unsound.

## What T1 can state

The graph already carries everything needed to describe these conversions:

  - `inputs[0]` exists and is stamped in all 376 cases;
  - inference refines that stamp;
  - `to_repr` says what the conversion produces.

`from_repr` adds no information. It is a second, staler copy of a fact the
edge already carries. The T1-clean move is to **stop emitting it** -- there
is then no derived field to go stale, no refresh pass, no `content_hash`
mutation problem, and no Graph replacement operation.

How T2 obtains the incoming repr is T2's business and is not specified here.

## Sites, if the field goes

Five constructions in `lib/SoN/FromOptree.pm`:

  - `:87`  `_coerce_to_str` -- samples `$node->stamp`, else `Unknown`. The
           210 stale values are all from here.
  - `:107` `_coerce_int_to_num` -- hardcoded `Int`
  - `:1665` list-to-scalar -- hardcoded `List`
  - `:3040` string-eval -- samples `$src->stamp`, else `Str`
  - `:3771` qr// -- hardcoded `Str`; the one false value

## Also observed, not acted on

44 Coerce nodes have an input whose stamp already equals `to_repr` -- they
convert a value to what it already is. Under the "declaration" reading they
look deliberate. Under "cache of the input" they are visibly redundant.
Whether the producer should elide them or a consumer should skip them is the
same boundary question and is not decided here.
