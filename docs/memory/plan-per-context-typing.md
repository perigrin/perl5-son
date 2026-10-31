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
