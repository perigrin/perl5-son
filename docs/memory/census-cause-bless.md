---
name: census-cause-bless
description: 430/430 goal, the bless half of "Call(method) has no class_name" (and its kin, ~27 cases) — a bless table keyed by address; ref() reads it; a package new is its sub; ROUNDTRIP 186 -> 190 of 431
metadata:
  type: project
---

**Cause:** "LLVM MOP: Call(method) X has no class_name" (7) and the
blessed-hash OO cases around it (~27 GAPs: ref() of an Unknown, bless,
dynamic_method, @ISA, isa, blessed, can). chalk had no bless; ref() of a
HashRef was the constant "HASH" -- so lowering bless as identity would
have printed HASH for a blessed hash, a silent wrong answer.

**Design: a bless table, not a header field.** bless keeps (address,
class) in a module table (@chalk_bless_set / @chalk_bless_get). The
reference and its contents are unchanged, so every copy of it sees the
class; nothing else in the backend changes. A header field would have
touched every %Array/%Hash allocation site.

**Built (chalk a7461882, perl5-son 51f3020 + a581883):**
- Analysis: bless's result is its reference's type; a package method
  call (target Chalk::MOP::Sub) is typed by its sub's return, replacing
  B::SoN's Object guess for any `->new` -- in a pass limited to package
  methods (run for every direct call, it retyped a list-context call
  List -> Array and broke builtin-join-lowers-a-static-list.t).
- a package's `new` runs its sub: _lower_call_method sent every `new`
  to the `class` constructor, which allocated a struct and never ran
  the sub (m2 "worked" only because its method ignored $_[0]).
- B::SoN keeps the invocant on a package `new`; only a feature class
  (SoN::ClassAux::is_class) has its kv args split into param_names.
- refused: a rebless, and ref() of a reference a bless elsewhere
  changes -- the class read would depend on lowering position.
- hash literals: `{ %a }` copies; undef / missed / tag-read values kept.

**Result:** 186 -> 190 (three runs agree); new: 052 053 054 078 . Next for the
bless family: dispatch on a runtime class (055, 180's grep), @ISA (056),
isa (058), blessed() (180), an object in a shared lexical (012, 059), an
object passed as an argument read through $_[0] typed Scalar (204).
