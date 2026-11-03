# Census cause: an element read left Unknown (386 -> 387)

**Cause:** "Subscript ... has repr=Unknown". An element of an aggregate
whose stored values nothing typed joined to Unknown, and the emitter refuses
Unknown. Audited Unknown refusals: 143, 175, 188, 198, 204, 212, 246.

## What changed (chalk d9df83cc, producer c7f56e6)
- `_element_repr`: an element joining to Unknown is at least Scalar
  (perigrin: `$a[0]` starts with `$`). Test:
  llvm-an-unknown-perl-bounds.t (143's program, red then green).
- That exposed a miscompile the refusal had hidden: `my @c = unpack("C*",
  ...); $c[2]` printed "" (stamped Undef as past the end). Both B::SoN's
  `_literal_element_type` and chalk's `_static_miss` counted an Unknown input
  as one element. Unknown now has unknown arity, like List/Array/Hash.
  Tests: wire-slice-flattens-into-array.t (new subtest),
  llvm-unpack-of-bytes.t test 8.

**Round-tripped:** 143.

**Tried and backed out:** bounding Unknown Calls by context. See
plan-t1-t2.md. It broke 12 cases and fixed none.

**Still refused for Unknown:** 175 (Subscript container Unknown), 188
(ArrayRef element Unknown). Both are plain-package method results. 198 and
204 are refused for other named reasons. 212 is a scalar deref of Unknown.
246 is `values %classes` with `$self` Unknown.
