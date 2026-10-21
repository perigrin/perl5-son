---
name: an-array-keeps-its-sigil-through-every-merge
description: an array's value through a ternary, a loop Phi, a `next` latch or a named version must stay `@` and stay lazy; each place that lost it was a silent miscompile chalk's Perl::Actions hit
metadata:
  type: feedback
---

Perl::Actions newly compiled and 60 chalk tests broke. One module, four
pre-existing holes, all about an array slot merged in a loop with
elsif arms:

- **Ternary stamp.** `_make_ternary` stamped only narrowed arms. An
  `@body = $s->@* if defined $s` merge of a deref (Array) and the loop's
  unstamped Phi was spelled `$phi71`, the last element. Fix:
  `StackSim::_joined_stamp` now walks through unstamped Phi and ternary
  arms to the `@`-sigiled PadAccess, and `_make_ternary` applies it.
- **Latch.** A `next` latch was always `$latchN`, so `$latchN = @phi`
  took a count. Fix: `_phi_var($ph) =~ s/phi/latch/`.
- **Named version declared ahead of its arm.** With `\@body` taken
  later, each whole assign is a named version `@body__N`. Its declaration
  floated to the deref's memory anchor, ahead of the elsif that guards
  it, and `($focus->@*)` died on a string. Fix: `_is_inline_aggregate` is
  true when only Phis and ternary arms read it.
- **Deref list read after `my ($x) = @_`.** The list-through-reference
  stale pass accepted only a Parameter at entry. A list-assigned
  PadAccess is defined by one Assign (floating means prologue, so entry).

Also: `COND ? @$x : ()` handed to a foreach, grep, map or call needs no
copy. A list slice of the ternary yields the elements themselves.
`\(C ? @a : ())` is `\@a`, so a reference keeps the refusal.

**Why:** each step reads correctly in isolation. Only a loop + elsif +
`next` + reference combination exposes all four. Chalk's action methods
are exactly that shape.

**How to apply:** after a chalk module newly compiles, bisect one failing
test (`bisect.pl`), then `ov1.sh MOD TESTS...` re-emits that module alone
and compares. Reduce from the method source, keeping the `\@x` and
`next` that make it bite.
