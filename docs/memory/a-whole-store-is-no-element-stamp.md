---
name: a-whole-store-is-no-element-stamp
description: an element read threaded to `@F = (...)` took that whole-array store's Array stamp; the renderer picks brackets by the container's stamp, so `$_->{name}` became `(...)["name"]`
metadata:
  type: feedback
---

B::SoN's `_floor_subscripts` gives an unstamped element read the stamp
of the Assign it is threaded to ("the stored type"). That holds for an
element store. A whole-aggregate store is stamped Array, and the
element became an "Array". The deparser's `_element` chooses `[...]`
or `->{...}` from the container's stamp before the `kind` field, so a
hash read of that element was spelled as a list subscript. That broke
LLVM::Context's `%_STR_IDX` and every LLVM test that used it.

Fix: only an Assign whose target is a Subscript, and only a scalar
type.

**How to apply:** an inference that copies a type from a neighbouring
node must check the neighbour has the same shape (element vs
aggregate). A corpus drift from Int to Scalar here was a correction:
the element held a reference.
