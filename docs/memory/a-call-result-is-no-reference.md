---
name: a-call-result-is-no-reference
description: a "mutated" array bound to a sort call was read as PostfixDeref over the call, spelled `(sort(@x))->@*`; the reader, not the many markers, is where to refuse the shape
metadata:
  type: feedback
---

`my @r = sort ...` binds `@r` to the sort Call node. A grep whose body
could write `$_` through a call marked that node in %MUTATED_LITERALS
(one of about ten marking sites). The padav reader then wrapped every
later read of `@r` in a PostfixDeref, which treats the call's list as a
reference. Chalk's BNF::Target::C died "Can't use an undefined value
as an ARRAY reference".

Fix: the padav reader skips the deref when the binding is a Call.

**How to apply:** when many sites set a flag and one consumer acts on
it, guard the consumer for shapes the action can't apply to. Patching
one marker (the first attempt here) misses the others.
