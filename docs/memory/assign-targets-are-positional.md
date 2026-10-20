---
name: assign-targets-are-positional
description: An Assign's target/value split cannot be keyed on node kind; three kinds appear on both sides
metadata:
  type: project
---

`SoN::Deparse`'s Assign branch splits inputs into `[targets..., values...]`
by walking while the input "is a target". Keying that on NODE KIND is wrong:
three kinds appear on BOTH sides, and each one cost a separate defect.

| kind | target in | source in |
|---|---|---|
| `ArgsSource` | `@_ = LIST` | `my ($a,$b) = @_` |
| `PostfixDeref` | `$$r = 7` | `my ($a,$b) = @$r` |
| `Constant` (undef) | `my (undef,$b) = @_` | `my $x;` |

**POSITION is the discriminating property.** The rules that hold:

- `ArgsSource` is a target only at index 0.
- `PostfixDeref` is a target at index 0, or before the last input — perl
  writes `($$r,$$s) = ...` with the derefs FIRST, never one after five pad
  slots.
- an undef `Constant` is a placeholder only in a list (`@in > 2`); a
  single-input Assign's undef is its VALUE (`my $x`).

**The failure is asymmetric and gets worse toward the end of the list.** A
wrongly-classified input at index 0 usually REFUSES ("no target slots"). One
later stops the walk before any target, so the whole list reads as values and
the emitted program prints NOTHING — measured, `my ($a, undef, $c) = @_`
emitted nothing where perl prints `13`.

Related: [[allow-lists-fail-asymmetrically]],
[[the-discriminating-property-is-arity]].
