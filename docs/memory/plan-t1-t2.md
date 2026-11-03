# Plan: the T1/T2 refactor (2026-11-03)

Decision: decision-start-t1-t2.md. Census held >= 386, DIFFERS 0, at
every step. Each step test-first.

## What exists (survey of chalk, 2026-11-03)
- Design: docs/plans/2026-09-04-t2-functor-architecture.md (1854 lines,
  the clean-slate T2-as-functor design; section 7 disposes of today's
  coercion sites). The solver: 2026-09-04-t2-the-solver-a-handoff.md,
  which introduces RuntimeRep. Background: 2026-08-31-t2-is-a-narrowing-
  analysis.md (a stamp is a SET of candidate machine types; narrow to
  one, else box as %Slot); 2026-09-04-unknown-carries-two-meanings.md
  (Unknown is an honest top; RuntimeRep handles it); 2026-09-04-
  publishing-the-arithmetic-family-fails.md (a measured revert, 224 ->
  184 -- read before touching arithmetic).
- Code: lib/Chalk/IR/Transform/T2.pm (331 lines, the narrowing analysis),
  wip/2026-09-04-t2-backend-migration.patch (the object half, unapplied).
- Today's backend (Context.pm, 20.7k lines):
  - `_repr_of` is the one read that honours per-lowering overrides
    (`cache{'repr:'.id}`). But 219 sites read `->stamp` directly, about
    2:1 against `_repr_of`, and they ignore the overrides.
  - Boxed-capable already: to-Str, coercion from Scalar, `//`,
    ternary/defined by slot, Phi merges of Slots, subscripts, hash and
    array element tags, shift/pop.
  - Requires a narrowed type: Divide/Modulo/Concat/bitwise, comparisons,
    && and ||, push values, join, length, keys, scalar deref,
    `_box_payload` for other reprs, fields.
  - About 80 refusals are repr-conditioned. Most are allow-lists, so
    Unknown fails by omission rather than by a named check.

## Steps
1. **One read.** Every repr read goes through `_repr_of`. This is the
   219 direct `->stamp` reads, done mechanically and in batches.
   Census-neutral; it's the seam the rest needs. Sonnet can do the
   batches, with a review of each diff. The ->stamp reads in die
   messages can stay.
2. **Decide once.** Before lowering, a T2 pass (start from T2.pm and the
   wip patch) gives each value node one repr: its narrowed machine type
   where one exists, else Scalar (%Slot). It's recorded where `_repr_of`
   reads it. Unknown becomes Scalar here, by decision, not by omission.
   Census-neutral by design; any case that moves is investigated.
3. **Boxed operations.** Teach each narrowed-only operation a Slot
   operand: dispatch on its tag at run time, or coerce by tag to the
   operation's type (the coercion matrix already unboxes by tag). Order
   by how many census refusals each unblocks. Each is its own
   test-first step; arithmetic last, after rereading the measured
   revert.
4. **Retire the allow-lists.** Refusals whose only reason was "not
   narrowed" go. The ones that remain name a real missing feature.
5. **Fold in:** derive %Slot's `defined` from tag != 0 (check the
   Opaque path first).

## Measures
- The census at every step (>= 386, DIFFERS 0).
- The count of repr-conditioned refusals, which should fall.
- The chalk suite: no file newly failing.

## Principle (perigrin, 2026-11-03): type and representation are orthogonal
- "The two are orthogonal but tangential to each other." A type is what
  a value is semantically; a representation is what it is mechanically.
  "They have no real relationship to each other except that the mapping
  should be optimal for translating between the two as effortlessly as
  possible."
- So the mapping is a choice, not a constraint: even "a Str can't live
  in an i64" is just an encoding we don't pick. T2 is an optimization:
  per value, choose the encoding that minimizes the total cost of
  conversions at its boundaries (producers, consumers, merges, calls).
  The boxed %Slot is always available; narrow encodings win where
  neighbours agree.
- In code: a read asks one axis or the other, never both. `->stamp` with
  `# static type` asks the type; `_repr_of` asks the representation.
  Where both are compared (inlined-argument binding, coercions), the
  mapping lives; step 2 routes those through the T2 map, not ad hoc
  comparisons.
- perigrin, 2026-11-03: "i64 is just a 64 bit segment of memory ...
  that's an 8 character string; average word length in English is a
  little under 5 characters." The small-string optimization (C++
  std::string, Rust compact_str): a Str of <= 8 bytes lives in the %Slot
  payload under a "short Str" tag. No malloc, no %Str header (today
  _box_payload mallocs a 24-byte %Str per boxed Str). It's the same
  type with a cheaper encoding, a candidate for the T2 solver after
  step 2. Caveats: bytes aren't characters (UTF-8), so length and
  encoding must ride somewhere (spare tag bits?); every Str consumer
  needs a short/heap branch.
- Step 1 batch 1 found a T2 seam: `_lower_as_repr` (an arithmetic
  operand) read via `_repr_of` sees a `Constant(undef)` held as Undef
  (its defined bit, i1) and has no Undef->Int conversion, so lli refused
  `add i64` over an i1 (llvm-a-use-typed-parameter.t case 5). Kept on
  the stamp, marked `# static type`, for step 2: the mapping needs an
  Undef -> numeric arrow (0), not a zext of the defined bit.

## Step 1 done (chalk 804c3edc, 807204d0, 1c894bd4, and batch 4)
- t/bootstrap/ir/repr-reads-go-through-repr-of.t ratchets direct
  `->stamp` reads in Context.pm: 213 -> 0. Every read now either goes
  through `_repr_of` or is marked `# static type`.
- About 38 reads asked how a value is held (converted); about 175
  deliberately ask the type (marked). So the seam was narrower than 213
  suggested: most reads ask what the analysis proved. Most of the real
  T1/T2 work is the mapping itself (step 2).
- The marked reads cluster into kinds, which step 2 should meet:
  - a node's own result type read at the start of its lowering, before
    it picks a repr (that's where the T2 decision belongs);
  - operands fed to arithmetic, coercions and slot building (the arrows:
    the Undef->numeric gap found in batch 1 is one);
  - argument binding: a declared type against a bound repr (the mapping
    in miniature);
  - "nothing typed" Unknown checks (become "boxed" once T2 decides);
  - producer-kind checks (Array/List/Hash literal), which are genuinely
    type questions and stay.
- Census held at 386, DIFFERS 0, across all four batches. Sonnet did
  the batches; each was reviewed and fully checked.

## Step 2 design: open question for perigrin (2026-11-03)
chalk's T2 design (docs/plans/2026-09-04-t2-functor-architecture.md, s.4)
does NOT overwrite stamps in place. It builds an IMAGE graph (a deep
copy) whose stamps are representations, inserting Coerce nodes where a
value changes encoding. The source graph keeps its types untouched, and
lowering becomes transcription. T2.pm (unwired) is the older,
overwrite-in-place version.

Options put to perigrin:
- A: overwrite in place. Poor fit: 171 backend reads need the type.
- B: a separate per-node repr decision read by `_repr_of`. Closest to
  today's backend; a small step from step 1.
- C: the image graph (the design). Cleanest separation; lowering is pure
  transcription; the 171 type reads must look up the source node.
- Recommendation: B now, aiming at C.

Settled (perigrin, 2026-11-03): Unknown does NOT map to %Slot. "Unknown
can't map to %Slot because %Slot is at least partially known ... Unknown
means we couldn't derive any type information ... Slot says we knew it
was at least a Scalar." Unknown is the lattice top (scalar, array, hash,
code, glob...); %Slot represents Scalar. So the design's refusal is
right, and the coverage trigger is a T1 gap: the analysis must derive
"at least Scalar" (or Array/Hash) where the producing op guarantees it
(a $ sigil, an element read, a scalar-context call). Then T2 maps
Scalar -> %Slot.

Also (perigrin): "I'm not sure a node should mutate itself." Nodes stay
immutable. The analysis decides types and T2 decides representations;
each publishes a table, not writes into nodes. Step 2 = a T2 side table
(node -> repr) built before lowering and read-only during it (option B
done this way, a lighter C). Debt to unwind: the backend writes
cache{'repr:'} during lowering; the analysis calls set_stamp widely; the
per-context copies call set_want/set_eval_want/set_stamp (fresh nodes,
at least); the scalar-only-method pass restamps calls in shared graphs.

## T1 rules that bound Unknown (perigrin, 2026-11-03)
- The sigil says what an expression yields: `$` means at least Scalar
  (a variable, an element `$a[0]`/`$h{k}`, a deref `$r->[0]`); `@` means
  a list (an array, or a slice `@a[..]`/`@h{..}`); `%` means a hash.
  ("An Array or Hash element starts with $, which falls back to rule 1.")
  In the graph the sigil isn't always on the node: a single-element
  Subscript is the `$` form. Where B::SoN drops the sigil or the
  element/slice distinction, that's a producer fix.
- A call's context bounds its result: list -> List (a scalar is a
  one-element list); scalar -> at least Scalar; void -> None (bottom: no
  value, no reader, the join identity). `want` on a Call is a type
  bound, not just a lowering hint. Void propagates into the callee
  (`return (f(), g())` evaluates f and g in void; wantarray is undef),
  so a void call could get a void per-context copy.
