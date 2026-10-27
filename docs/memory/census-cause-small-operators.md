---
name: census-cause-small-operators
description: 430/430 goal, "cannot lower op=Power/Repeat/LeftShift/Negate" (038 039 041 048 264 266) -- ** x << >> and unary minus on numbers; older wrong: a float -0 printed "-0"; 258 -> 264
metadata:
  type: project
---

**Cause:** small operators never lowered: Power (038 041), Repeat (039
264), LeftShift/RightShift (048 266), Negate (038's next).

**Built (chalk 65a48acc):** `_lower_power` (C `pow`, Num), `_lower_repeat`
(string only; malloc len*n, memcpy loop, n<1 -> ""; a list repeated
refused), `_lower_shift` (shl/lshr; count >= 64 -> 0; negative operand or
count, or a shl result past an i64 -- perl's is a UV -- stops),
`_lower_negate` (Int `sub 0,x`, Num `fneg`; perl negates a STRING's text:
static Str refused, a Scalar whose tag is Str stops). Helpers
`_operand_as`, `_stop_unless`. Machine types through `_repr_to_llvm_type`
(llvm-repr-machine-type-seam.t guards literal `double`).

**Older silent wrong fixed:** a Num zero with its sign bit printed "-0"
(%.15g); perl prints "0" (`-1.5 * 0`). `_emit_to_str` Num selects "0" for
`fcmp oeq x, 0.0`.

**Result:** 038 039 041 048 264 266 round-trip; 258 -> 264.

**Also tried and reverted:** narrowing "an element of an array that may
grow" to growth before the aliasing loop -- sound, but no probe or corpus
case went from refused to perl's answer (190 198 are refused further on),
so no test failed first. Kept out.
