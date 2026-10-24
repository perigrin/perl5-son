---
name: census-cause-assign-scalar-is-increment
description: 430/430 goal, cause "Assign with repr=Scalar reached LLVM backend" (11 cases) — really perl's ++ (B::SoN Increment) unlowered; @chalk_slot_inc with the magic string increment; exposed // over a Str and non-Str hash keys; ROUNDTRIP 111 -> 122
metadata:
  type: project
---

**Cause:** "Assign with repr=Scalar reached LLVM backend" held 11 cases
at 4f87f780. The Assign was only the messenger. Its value was an
`Increment`, B::SoN's node for `++` on a value not proven a number, and
chalk had no lowering for it at all.

**Perl's ++, measured** (perl is the oracle, and memory was wrong twice):
- The magic pattern is checked BEFORE numeric-ness, so a whole string
  of letters then digits counts in its own alphabet. `"007"++` is
  `"008"`, `"9"++` is `"10"`, `"inf"++` is `"ing"`, `"Zz9"++` is
  `"AAa0"`.
- Any other string is its leading number plus one: `" 3"` gives 4,
  `"0x1A"` gives 1, `"a-b"` gives 1.
- `""++` is 1, and undef is 1. The old value of `undef++` is 0; the
  producer already spells that as `// 0`.
- IV_MAX++ is an unsigned integer in perl. A Slot can't hold that, so
  it exits 255.

**Built:** `@chalk_slot_inc(%Slot)` and `@chalk_str_inc(%Str*)` as IR
helpers, called from `_lower_increment`. The blanket Assign-of-Scalar
refusal is gone; the census showed no wrong answer from removing it.
The Num type in the helpers comes from the type map, as
llvm-repr-machine-type-seam.t requires.

**Exposed next, each fixed with a test that failed first:**
- `$str // 0` into a Scalar result phied the unboxed Str (unary.md). A
  definite LHS is defined, so the result is the LHS, boxed.
- A hash key that was not a Str (an element, an Int, a Num, a literal
  key) was taken apart as a %Str (chalk-found-gaps.md, `$seen{$x}++`).
  `_hash_key_str` converts it at every key site.

**Round-tripped:** 111 -> 122, 0 wrong.
