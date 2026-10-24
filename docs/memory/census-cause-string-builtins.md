---
name: census-cause-string-builtins
description: 430/430 goal, builtins uc/lc/ucfirst/lcfirst and rvalue substr (6+6 cases) as IR helpers; a non-ASCII string constant was an LLI failure since baseline, now a named GAP (chalk strings are bytes, perl's ops are characters); ROUNDTRIP 136 -> 139
metadata:
  type: project
---

**Causes:** "cannot lower op=Call builtin uc" (6 cases) and "builtin
substr" (6 cases) at 83ed09e2.

**Built:**
- `@chalk_case(ptr, len, mode)` covers uc, lc, ucfirst and lcfirst. It
  is exact for ASCII. A byte past ASCII read at runtime exits 255.
- `@chalk_substr` is a NUL-terminated copy. The NUL matters because a
  number read from the substring must stop at its end. Offset and length
  follow perl's rules, measured against perl: a negative offset counts
  from the end, a negative length leaves that many off the end, and a
  length past the end is clamped. Outside the string perl gives undef;
  that exits 255.
- The 4-argument and lvalue `substr` stay refused (004, 337).

**Found:** a string constant with a character past ASCII was an LLI
failure at baseline. The global's declared size disagreed with its
bytes. Sizing it right would only turn a crash into a wrong answer:
chalk strings are bytes, and perl's `length`, `substr` and `uc` act on
characters. It is refused by name in the Constant lowering, NOT in the
shared `_module_global_name`. A unit test pins that helper's byte-length
contract; I broke it once by putting the refusal there.

**Character semantics are a whole feature:** decoding, character
length and case mapping. It is the right next step for any corpus case
with non-ASCII text.

**Round-tripped:** 136 -> 139.
