---
name: a-lifted-closure-loses-its-makers-parameters
description: The deparser lifts closures to file scope; a capture of a signature parameter or a field then names nothing
metadata:
  type: feedback
---

A lifted anon body shares its captures through file-scope `my`s, and the
maker's own `my` of them is suppressed. Neither works for a signature
parameter (`method leaves($node_class = undef)` declares its own) or a
field (each instance has one): chalk's Context::leaves filter let every
node through; IR::Graph::nodes's closure over `%cache` was refused.

**Why:** the shared-variable model is a stand-in for perl's closures. It
also gets `counter()` called twice wrong (`0123` for `0102`) -- still open.

**How to apply:** a body that reads a field or captures its maker's
parameter is emitted as `my $closure = sub {...};` at the top of the maker
(`%closure_var`), and calls and references go through the variable. The
proper fix is inline closures everywhere; until then, check a closure test
with two instances.
