---
name: a-read-that-names-a-version-is-half-a-rule
description: "Audit 2026-11-22, risk 4: a floating read names its memory version, and nothing made the consumer read it before the next store; chalk's chain walk now makes every read at a node's mem_in before that node (Click's anti-dependence)"
metadata:
  type: project
---

`my ($x,$y)=(1,2); my $r=\$x; ($x,$y)=($y,$x)` printed `2 2` for `2 1`.
B::SoN's wire was right: the read of `$x` at the version before the list
assign is both its target and `$y`'s new value. T2 set the target's memo to
the new element, so the later use of that read got the stored value.

**Fix (chalk, by class):** Control.pm's chain walk calls `reads_before`
on the `mem_in` of every node with `mem_out`, before lowering it -- every
read at the version that node kills is made first, whatever kind the node
is. `list_assign` keeps the pre-store memo of a target kept in memory.

**Not closed by it:** a `my` aggregate a sub also reaches (B::SoN's
`shared`) is read where it is used, not copied at its version, because T2
takes a shared PadAccess for the variable itself -- copying it made a list
assign fill a copy. WireCheck refuses such a read (or such an argument)
before a sub call that may change it (W10).

**Lesson:** "every read names a version" is half the memory model. The
other half is that the consumer makes the read before the version is
overwritten; check it in the consumer's scheduler, not per shape.

Related: [[every-read-names-a-version]], [[a-verifier-that-reads-a-derived-flag-checks-itself]].
