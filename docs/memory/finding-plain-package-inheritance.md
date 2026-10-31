# Finding: plain-package inheritance isn't wired end to end (2026-10-31)

pvm 056: `package Derived; our @ISA = ("Base"); ... $o->SUPER::hi()`.
perigrin decided to support it (decision-remaining-refusals.md).

**Measured.** Even compile-time `use parent -norequire, "Base"` fails:
- B::SoN emits no class record for a package with no subs of its own
  (Derived is missing from `classes`), and `parent` is set only for
  feature classes (`SoN::ClassAux::superclass_name`). `_empty_class`
  gives every plain package `parent => undef`.
- chalk: "Call(method) 'main::SUPER::hi' on undeclared class 'Derived'
  ... not in the sealed MOP".
- The runtime form arrives in the program graph as
  `EntryWrite(EntryDef @Derived::ISA, ArrayLiteral(Constant "Base"))` on
  the main control chain. chalk refuses it at `_pkg_aggregate_ptr`
  (@ISA is in %_PERLS_AGGREGATE).

**Shape of the fix.**
1. Producer: a class record for every package that's blessed into or
   has @ISA, with `parent` taken from the stash's @ISA at walk time
   (covers `use parent`), or from a constant one-element @ISA EntryWrite
   on the main line before any method call.
2. chalk: plain-package method dispatch through the parent chain;
   `SUPER::m` resolves from the call site's package; the constant @ISA
   write becomes a no-op once the registry holds it. Other @ISA reads
   and writes stay refused.
