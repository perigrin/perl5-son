# Plan: per-context typing (perigrin chose it, 2026-10-31)

Covers 091, 092, 129, 141, 144. perigrin: "Isn't this a type inference
question?", "List|Scalar is equivalent to List", and a hash assign
returns Hash. See decision-remaining-refusals.md (Update 2026-10-31).

## Done (step 1)
- A block eval whose context is its caller's (the producer spells it
  `eval_want => 'runtime'`) resolves to the inlined call's context
  (`_inline_want`). Scalar or void then take undef on a die, as a scalar
  eval does. Test: llvm-an-eval-in-list-or-callers-context.t.

## Measured blocker (step 2)
- A list-context eval that can die must yield the empty list. Building
  its value as an %Array* in close_eval works, but the readers (the
  `@r = ...` literal, join, print) read the node's stamp (Scalar) and
  take one %Slot: lli refused "defined with type ptr but expected %Slot".
- Restamping the node isn't safe: an inlined sub's graph is shared by
  every call site (091 calls w in list and scalar context), so a stamp
  set at one site leaks into the next.
- So the type must be decided per calling context in the analysis:
  type (or copy) the callee once per context it's called in, so a
  list-context site's eval/return nodes carry List and a scalar site's
  carry Scalar. That's monomorphization by context, the plan perigrin
  approved. Inlining already lowers per site; what's missing is typing
  per site.

## Also
- B::SoN refuses an eval body that leaves several values ("its value
  merges only the last element"): a producer gap for list eval bodies.

## Decision (perigrin, 2026-10-31): copy per context in the chalk loader

The chalk loader clones a sub's graph once per context it's called in
(list, scalar; void counts as scalar), before Analysis runs. Each call
names its copy, and each copy is stamped for its context. The type
decision stays in chalk. The alternatives were B::SoN emitting variants,
or parking the five cases.

### Steps
1. A graph clone in chalk: nodes, inputs, control_in, regions, phis,
   memory chains, ids fresh per copy. Test: a clone lowers and runs the
   same as its original.
2. In the loader: for each sub called in more than one context, clone
   it per context and point each Call's target at its context's copy.
   The copy records its context.
3. In Analysis: within a copy, a `runtime`-context node (an eval, a
   return's value, a call in return position) takes the copy's
   context. In list context its value is List/Array-typed; in scalar
   context it follows the producing op's scalar rule.
4. Lowering: list-context eval yields an empty array on a die (the
   blocked step 2); 129, 141 and 144 per their ops' rules.

## Step 2 landed (chalk 72e38a77; 382 -> 383)
- Serialize::JSON: `%CONTEXT_COPY`. A sub with a `runtime`-context node,
  called somewhere in list context, is deserialized again as
  "NAME@list". The copy's runtime eval Region becomes `list`. After
  Analysis, its eval phis are stamped List (the passes join the arms to
  Scalar first).
- Analysis `_attach_call_targets`: a direct call with want=list of such
  a sub targets a MOP::Sub on the copy (field `context => 'list'`), and
  the call (its site's own node) is stamped List.
- close_eval: when every phi is typed List or Array, a list eval that
  can die is built as %Array* (the body's value, or empty when caught).
  A shared node is never retyped while lowering.
- Round-tripped: 091.
- Found: a `die` in a sort comparator was dropped (`[1 2 3]` where perl
  dies), pre-existing and masked in 092 by the list-eval refusal. Now
  refused by name (llvm-a-sort-comparator-that-dies.t). Added to the
  report list.
- Next: 129, 141, 144 (scalar-context faces of a returned list or hash
  assign), 092 (a comparator's die reaching its eval).

## Step 3: scalar copies (chalk 40fb3bc7; 383 -> 384)
- A sub that returns a direct call with no context of its own (`return
  g()`, made in f's caller's context, so f's Return has no scalar face)
  gets a copy per context it's called in. Scalar always. List only when
  the callee doesn't itself return such a call; ev/od, calling each
  other, broke when every list call got a copy.
- In the copy that call takes the context (`Call::set_want`). In a scalar
  copy, the call and the Phis to its Return are left untyped by the
  loader. A pass over the copies only (`_resolve_direct_calls(...,
  per_context)`) types them from the callee's scalar face
  (return_reading_for_want), Scalar included.
- Only a copy made for a caller's-context eval (`%CONTEXT_COPY_EVAL`)
  types its list-context call List. Forcing List on a returned-call copy
  broke 070, 079, 080, 084 and 176 (`build` returns a string). Making
  the face rules global changed nothing for them; the forced List did.
- is-narrowed-guards.t: a guard uses `_stamp_is_absent`, never
  `defined ->stamp`.
- Round-tripped: 129. Next: 141 and 144 (a hash-assign or bare-return
  scalar face), 092 (a comparator's die).
