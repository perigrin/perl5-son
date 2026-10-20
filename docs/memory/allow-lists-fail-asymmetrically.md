---
name: allow-lists-fail-asymmetrically
description: A phantom name in an allow-list silently drops a valid case; protect it by construction or by test
metadata:
  type: feedback
---

An allow-list and a deny-list fail in opposite directions, and the allow-list's
direction is silent.

In a DENY-list, a name matching nothing is dead weight — harmless.
In an ALLOW-list, a name matching nothing means the thing it was meant to name
is ABSENT from the set, so a valid case gets refused.

Measured instance: the map/grep contribution allow-list in `SoN::FromOptree`
was written from memory with twenty phantom names (`Chr`, `Ord`, `Sprintf`,
`Join`, `Ternary`...). `Ternary` matching nothing is why the real `TernaryExpr`
was missing, and `comp/retainedlines.t` began refusing a body that was fine.

**Why:** `SoN::IR::NodeFactory`'s registry cannot have this bug, because it maps
a name to `"SoN::IR::Node::$_"` — a wrong name dies at class load. The
protection is in the CONSTRUCTION, not in anyone checking. Any second list keyed
on those same names is a bare set of strings and inherits none of it.

**How to apply:** when writing an allow-list, either derive it so a wrong name
fails loudly (name-to-class mapping), or add a test asserting every entry names
something real — and verify that test fails by injecting a phantom. Never write
one from recall. See `t/from-optree-arity-allowlist-names.t`.

Related: the same bug was fixed three times before the allow-list, each keyed on
a property that was a proxy for the real one ([[the-discriminating-property-is-arity]]).
