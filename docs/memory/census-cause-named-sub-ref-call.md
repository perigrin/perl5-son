# Census cause: a call through `\&name` (lattice TOP)

**Cause:** "X is the lattice TOP" for 067. The method `ref_other { my $r =
\&Other::helper; $r->() }` returned an indirect call that B::SoN stamps
Unknown, so the method had no type.

**Round-tripped:** 067 and 250 (275 -> 277). 102 (a signature default calling a
sub, `Add` over an Unknown Phi) and 246 (a method returning `values %h`) still
hit TOP.

## What was done

- **Analysis** `_type_calls_through_named_refs`: an indirect Call of
  `Ref(Constant code NAME)` gets NAME's sub as its target. When every Return of
  that sub has the same scalar stamp, the call gets that stamp.
- **Lowering:** `_lower_call_indirect` routes such a call through `_call_via` as
  a direct call of the target, which inlines it.

## Refused by name

- `\&f` taken before a glob reassignment of `f` (perl calls the new code).
- `\&nope` of an undefined sub.
- A callee whose return is not a single scalar type.

Test: chalk `t/bootstrap/ir/llvm-a-call-through-a-named-sub-ref-has-its-type.t`.
Probes nr1-nr6: ROUNDTRIP or refused by name.
