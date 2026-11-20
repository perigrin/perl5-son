---
name: a-bless-only-arm-loses-its-if
description: "`if (C) { bless $o, 'X' }` emits no If: the bless hangs off the control before the test beside the next statement (two successors), and the ref() after reads MemStart. At cc9d970 and at placement-pins 9d66925. chalk refuses it (a control node with N successors); probe cr8"
metadata:
  type: project
---

Found from chalk (branch chalk-arms, 2026-11-20) while testing class reads
across a bless. Producer cc9d970; placement-pins 9d66925 gives the same wire,
so it is older than the class-read work.

    my $o = {}; if (@ARGV) { bless $o, "X" } print ref($o), "\n";

The wire has NO `If`. `Call bless [o, "X", MemStart]` has `control_in` the
HashLiteral, and so does the `Print`: one control, two successors. The
`Count(@ARGV)` is left with no consumer. `RefType(o, MemStart)` reads before
the bless. With an else arm that also only blesses (probe cr8) there are
three successors.

    my $h = {}; my $r; if (@ARGV) { $r = "n" } else { $r = ref($h); bless $h, "K" } ...

is the same: the arms become a `TernaryExpr` for `$r` and the bless is left
on the control above.

An arm with any other statement in it keeps its If (`{ bless $o, "X"; print
"x" }` is `If` / `Proj` / bless / Print / Region, and the RefType after
reads the memory Phi) -- so it is the arm whose only effect is the bless
that is taken for a pure arm and if-converted.

**Why:** bless is a version now (`version => 1` in the effect table), but
whatever decides "this arm has no effect, drop the diamond" does not ask the
effect table; it was written when bless carried no memory.

**How to apply:** find the pure-arm test (the same one that makes `$r = C ?
"n" : ref($h)` a TernaryExpr) and make it ask `B::SoN::EffectTable` for a
version/effect; then cr8 should be SAME in chalk with no chalk change (an If
whose arm is a pinned bless lowers today). chalk's answer meanwhile is a loud
refusal: "a control node with 2 successors".

Related: [[a-class-read-names-its-memory-version]],
[[chalk-takes-the-class-read-wire]], [[the-effect-table-is-the-one-statement]].
