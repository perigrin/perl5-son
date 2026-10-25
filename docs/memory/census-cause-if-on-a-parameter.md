---
name: census-cause-if-on-a-parameter
description: 430/430 goal, cause "cannot lower If.cond[Unknown->Boolean]" (8) — an if over an untyped sub parameter tests the caller's value (_repr_of); exposed a Slot bitcast in an array deref and a merge mistaken for a nested array; ROUNDTRIP 181 -> 184 of 431
metadata:
  type: project
---

**Cause:** "cannot lower If.cond[Unknown->Boolean]" held 8 cases at
b129e72f. `my ($want) = @_; if ($want)`: nothing in the sub types the
parameter, so it is Unknown. Inlined at a call it IS the caller's value;
_repr_of already answered that for containers and coercions, and the If
condition did not ask it.

**Built (chalk dac75cce):** the If condition's repr is _repr_of(cond).
Test: llvm-an-if-on-a-parameter-tests-what-was-passed.t (failed 3/3).

**Exposed, would have been LLI_FAIL (pvm 211):**
`for ($e ? @{ $r->{s} // [] } : ())`
- the array deref of a `//` merge (a Slot) bitcast it as a pointer; it
  now reads the tag: ArrayRef payload, undef an empty array (rvalue
  `@{ undef }`), anything else exits 255;
- Analysis's _element_repr took a literal whose one element is a Phi of
  an array and a list for chalk's own nested array; a merge's array
  flattens, as a call's does.
Test: llvm-a-deref-reads-its-reference-by-tag.t (failed 2/2).

**Result:** 3 of 8 round-tripped (079, 157, 211). Next: a Num carried
into a Str loop phi at a jump merge (093), a Phi of an Int and a List
(129), Phi[Scalar -> Unknown] (165), If.cond[Array->Boolean] -- an
array's truth is its count (174), a join over an Int (216).

**How to apply:** when a fix lowers a case further, its next failure may
be an emitted-IR crash, not a refusal -- check the census bucket moved
to ROUNDTRIP or GAP, never LLI_FAIL.
