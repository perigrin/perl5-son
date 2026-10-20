---
name: one-node-two-consumers-runs-twice
description: A side-effecting IR node read by two consumers is emitted twice by the deparser; bind it once at its store
metadata:
  type: project
---

In SoN::Deparse a value node with a side effect and TWO consumers gets
rendered once per consumer, so the emitted program performs the effect
twice. Found on `RegexSubst`, which feeds both the store that writes the
string back and the `RegexSubstCount` that takes the number:

    our $s="aaa"; my $n = ($s =~ s/a/b/g);
      perl : 3 bbb
      emit : " bbb"    -- second pass saw `bbb`, matched nothing, counted 0

The fix is to emit the effect ONCE at its store site, bound, and have the
other consumer read the binding.

**Two results need two maps.** `%bound` already held the substituted
STRING for that node. Reusing it for the count made a loop's ordinary
`$effN` binding (installed by the generic chain walker, holding the
string) be read as a number -- `bbb bbb` instead of `3 bbb`. The count
variable lives in its own `%subst_count_var`.

**The store path decides whether the fix reaches.** An `EntryWrite` store
is reached before the chain walker binds the node, so replacing it works.
An `Assign` store (the `foreach` write-back) is reached AFTER, so the same
code ADDS a third statement instead of replacing one. That half is
deliberately unfixed; suppressing the earlier binding is a chain-walker
change.

Related: [[read-generated-output-not-tests]] -- the green suite never saw
any of this. Only running the emitted program did.
