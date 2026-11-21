---
name: a-memory-edge-is-not-a-version
description: "Wire v2 stage 5: the 14 census cases v1 lowered and v2 did not were two chalk causes -- an Impl class compiled at wire 1 into a v2 wire, and 'has a mem_in' asked where 'is a version (mem_out)' was meant"
metadata:
  type: project
---

Wire v2 stage 5 (branches `v2-s5`, 2026-11-21). The census on wire 2 was
412 for v1's 426; all 14 were T2 "out of its slices", none a v2 shape T2
lacked:

- **An Impl class was linked in at wire 1.** A program naming %SIG, %INC or
  a stash gets chalk's metaobject class linked into its wire
  (`Chalk::Impl::link_json`), which B::SoN compiled without `wire=`. v1
  graphs inside a v2 wire are not upgraded (the loader upgrades by the
  wire's version), so their memory stayed a positional input: "a bless of
  one argument" was bless, class, memory; a PadAccess with its memory as an
  input is "no location". 027, 013, 316-319, 346. `Impl::wire($class,
  $version)` now compiles at the program's wire, cached per version.
- **A memory edge is not a version.** On v2 every pinned read names the
  memory it follows (`_pin` gives mem_in to what touches memory). On v1 a
  pinned Ref had a memory input only when taken where it stands.
  `Ref::taken_where_it_stands` asked `defined memory_operand`, so a foreach
  alias's `\$a[$i]` (pinned to order, no version) was taken for one taken
  where it stands and refused for its index. It reads `mem_out` now. 073 123
  188 195 217 232 233.

**How to apply:** where chalk asks "does this read take memory as an
operand", v2 answers "does it name a version" for every pinned read; ask
`mem_out` for "is it a version", and grep `memory_operand` / `blessed(
->mem_in )` users when a v2-only refusal shows up. Run a T2 test at both
wires (t/bootstrap/ir/t2-reads-a-v2-wire.t does).

**Found on the way, open:** `our $g; sub f { ... $g = ... } print f(1), $g,
f(0), $g` prints `1122` for perl's `1222`, on both wires: perl puts `$g`
itself on print's stack (an alias), so both reads see the last store; B::SoN
reads it at its version. A silent wrong answer, not v2's; not fixed.

Related: [[the-loader-holds-v2-to-its-invariant]], [[the-wire-names-its-memory-edges]].
