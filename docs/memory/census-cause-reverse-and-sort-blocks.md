---
name: census-cause-reverse-and-sort-blocks
description: 430/430 goal, "Call builtin reverse" (4) and "sort with no folded comparator" (4) -- reverse both contexts; sort runs its block; <=>/cmp had no lowering at all; 206 -> 210 of 431
metadata:
  type: project
---

**Causes:** "cannot lower op=Call builtin reverse" (003 105 162 310) and
"sort with no folded comparator" (087 088 092 217).

**Built (chalk a7cecdca):**
- reverse: in a list, its arguments flattened, pushed back to front; in
  scalar context (stamp Str), joined with "" and the bytes reversed. A
  byte past ASCII exits 255 (perl reverses characters). With no
  arguments in a list it's empty (B::SoN folds `reverse @e` to no
  inputs); in scalar context that would be $_ and is refused.
- sort block: chalk's loader had DROPPED sort_cmp_body. The Call now
  keeps it and sort_package, and Analysis attaches a metaobject over the
  comparator graph (same %anon cache as anonymous subs). The insertion
  sort inlines the block per comparison through `_call_via`, binding the
  graph's EntryDef $a/$b (in sort_package) to the two slots. It swaps
  when the block's value (coerced to Num) is > 0, which is stable, like
  perl's merge sort. A block writing $a/$b is refused.
- `<=>` and `cmp` had NO lowering (op=NumCmp/StrCmp fell to the generic
  GAP). `<=>` is zext(gt) - zext(lt): exact over two Ints, doubles
  otherwise, and a NaN (perl: undef) exits 255. `cmp` is memcmp over the
  shorter length, then length.

**Guard tests that fired:** llvm-repr-machine-type-seam.t forbids a literal
`double` at an emit site; use _repr_to_llvm_type('Num').
is-narrowed-guards.t forbids `defined $node->stamp` in Analysis guards.

**Not built, and why:**
- Bitwise ops (046 049 050): without the bitwise feature, `&` on two
  strings is a STRING op. B::SoN coerces the operands to Int, so whether
  perl does a string or numeric op depends on a run-time type chalk can no
  longer see. Only `use v5.28`'s numeric flavor (051) is sound.
- Remaining sort cases: 087 (method on the elements: dispatch), 088 (`if
  (!@ARGV)`: an Array condition), 092 (an eval in list context that can
  die), 217 (a Region Phi Int->List).
