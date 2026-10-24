---
name: census-cause-package-methods
description: 430/430 goal, cause "Call(method) X is absent from class X vtable — available methods: []" (7) — blessed-hash OO methods are package subs; slurpy @_ targets, hole-tolerant positional binding, signature count from the wire; ROUNDTRIP 140 -> 142 of 431
metadata:
  type: project
---

**Cause:** "LLVM MOP: Call(method) X is absent from class X vtable —
available methods: []" held 7 cases at 8beb4a2a. All of them are
blessed-hash OO, where a package's methods are plain subs and the
vtable (built from `class` methods) has no slot for them.

**Built:**
- `_attach_call_targets` resolves a method name the class doesn't know
  to the package's own sub (not inherited through `@ISA`).
- `_lower_call_method` hands a call whose target is a plain sub to
  `_lower_call_direct`, with the invocant as argument 0.
- `my ($self, @rest) = @_`: the slurpy `@rest` is bound to an array of
  the remaining arguments, at every PadAccess of it in the callee.
- Positional reads bind by index with holes, because a method reads
  `$_[1]` and never `$_[0]`.
- A signature's full positional count comes from the wire's
  `signature.mandatory`, now carried on MOP::Sub. Despite its name,
  that field counts every positional parameter, and `params` lists
  only named ones.
- A reference or object argument is a scalar in `@_`, not a flattening.

**Rejected:** treating Int→Str as value-keeping for an inlined
argument. A Str read back as a number goes through strtod, which loses
digits on integers past 2^53; `%KEEPS`'s own comment records the same
failure. Case 060 stays refused on that.

**Round-tripped:** 140 -> 142 (146 and others).

**What the rest hit:** Unknown stamps on call results (If.cond, a
Region.Phi with an Unknown arm), Subscript over an Object (`$self->{k}`
hash-based objects), and a store into a Scalar-typed container.
Blessed-hash objects as hashes are the next feature in this line.
