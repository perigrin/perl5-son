---
name: a-call-s-stores-are-its-mod-set
description: "SILENT WRONG fixed (ag30, 1201 for 1101): an element operand a later call may store is read again, guarded by an Exists made beside its first read; what a call may store is the callee's MOD set (SoN::FromOptree::ModSets), transitive; reshape/replace and unknown calls refused by name"
metadata:
  type: project
---

Branch `fix-mod-sets` (2026-11-21), perigrin's option (a) from
[[an-element-is-an-alias-a-call-can-store]].

**The rule (perl).** `print f(1), $r->[0], f(0), $r->[0]` pushes the element
itself, so print reads it after f(0) stored it: 1101. But only if the element
EXISTED when pushed -- else perl pushes undef, and a store the call makes
later is not seen (ag34: `($r->[0], f())` with f making it gives undef).

**The fix (producer only; no wire change).**
- `SoN::FromOptree::ModSets`: per sub, the locations it may store -- a
  package variable (`N:`), a lexical by the pad that DECLARES it (a capture is
  followed OUTSIDE: `L:`), a field (`F:`), a container through a reference
  (`R:array|hash|scalar`), its own arguments (`P`), unknown (`U`) -- with the
  key stored and whether the container is RESHAPED (shift, splice, delete,
  `@a = ...`). Transitive by a fixpoint over the call graph; a callee's `P`
  is mapped onto the call's arguments; a method is every program sub of its
  name; `my $c = \&f` stored once resolves `$c->()`. Builtins that store
  their operand are `B::SoN::EffectTable::stores_operands`.
- `_elem_alias_plan`: a later call whose effects may store the element ->
  read again; may reshape its container or replace what holds it (the `$r`,
  an outer `$r->{a}` of `$r->{a}{b}`) or unknown -> GAP by name. Perl frees
  the aliased SV there (`$r = [7]` in f printed "" for `print $r->[0], f()`).
- `_step` wraps the element read: when the plan says re-read, an Exists of
  the same container/key at the same memory is made beside it; the consumer
  replaces the slot with `TernaryExpr(Exists, Subscript(now), Subscript(then))`.
- Scalars: a later chomp/chop/s///, tr///, list assign of the operand now
  counts as its store (`print $x, chomp($x)` was `a\n1`, perl `a1`).

**Precision that kept corpus 009 and chalk's lib:** two constant keys that
differ are different elements; a lexical the caller declares is reached by a
reference only if one is taken; a callee's own `my` is seen by no caller
(dropped from its summary, kept at the caller's own call site).

**Still open (named, not silent):** a direct store into the same container
through ANOTHER reference in a later operand (not a call); an element
operand of a `?:` (a LOGOP consumer is skipped, as for scalars); implicit
calls (overload, tie, DESTROY); a method dispatched to a class outside the
program that shares a name with a program sub.

**Found on the way, not fixed:** `print $x, (($x, $y) = (5, 6))` drops `$x`
(prints 56 for perl's 556), and `scalar(($x,$y) = ...)` as a print operand
renders as the list -- both before this branch too.

**How to apply:** an alias question is "what may the later operands store",
and for a call that is a summary, not "any call": refusing every call cost
real programs, and a summary with a few precise distinctions (keys, own
lexicals, kinds) keeps them. Re-reading is safe only where the alias still
names the element: guard on existence, and refuse reshape.
