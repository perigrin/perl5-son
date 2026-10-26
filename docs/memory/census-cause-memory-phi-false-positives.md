---
name: census-cause-memory-phi-false-positives
description: 430/430 goal, "element read across a branch-guarded store needs a memory-Phi" (6) -- two of them were not branch-guarded at all (a list assign READING elements was taken for an element store); unblocked, 123 then showed two older invalid-IR derefs; also 071 (an untyped Region Phi typed by its arms)
metadata:
  type: project
---

**Cause:** "element read across a branch-guarded store needs a memory-Phi"
(123 125 166 191 232 233).

**What it really held:** `_is_element_store` returned true for ANY Subscript
input of an Assign -- the VALUES a list assignment reads, too. `my ($lv,
$val) = ($r->[0][0], $r->[0][1])` (no control input, off the effect chain)
then made the whole graph "branch-guarded", and every element read refused.
It now checks only the TARGETS (the first `targets` inputs; 1 for a scalar
assign). 166 and 123 lower.

**What 123 hit next -- two older invalid-IR derefs (wrong at HEAD):**
- `keys $obj->{n}->%*`: `_lower_hash_deref` bitcast its operand as an i8*
  whatever it was; an element of a blessed hash is a %Slot. It now reads
  the tag as `_lower_array_deref` does: HashRef -> its payload, undef -> an
  empty hash, anything else exits 255.
- `@{ $h{missing} }` / `%{ ... }` where the read is stamped Undef (the key
  known missing) bitcast an i1. Undef is now an empty list / hash.

**perl surprise, recorded:** rvalue `@{ undef }` COUNTED is undef, not 0
(`print scalar(@{ $h{z} })` prints ""). A count of a deref of a known-undef
is refused by name; a copy (`my @l = @{ undef }`) is a real empty array and
counts 0. KNOWN WRONG, older, left with a `shortcut:` comment: the tag-read
path counts a run-time undef as 0 -- refusing it would refuse every
`scalar @{ $h{k} }`. The fix is a Count that yields a Scalar there.

**071 (same round):** a sub falling off `return "none" unless $k` returns
$k; the Region Phi of a Str and an inlined argument was Unknown. Typed from
its arms' `_repr_of` per lowering (cache `repr:<id>`, as And/Or), and
`_coerce_arm` reads `_repr_of` too.

**Still refused:** 125 and 191 (true branch-/loop-guarded stores), 232 and
233 (a Subscript container typed Unknown: `vars()->{$k}` through a call).
