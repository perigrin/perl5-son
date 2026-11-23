---
name: pending-bug-foreach-write-back-later-in-a-loop-body
description: "CLOSED (branch loop-writeback): a read of an array early in a loop body flattened the literal though the body wrote it later -- any write: a foreach alias, a callee's `$_`, a slice, a map's `$_`, an inner loop, before a `return @a`; the loop learns the slot at sealing and its header marks it"
metadata:
  type: project
---

CLOSED 2026-11-23, branch `loop-writeback` (producer cc4e0db). Found while
accounting for the 9b proof's rows (baseline section 19).

    my @a = (1,2); my @r;
    for my $i (1..2) { push @r, join(",", @a); for (@a) { $_ .= "x" } }
    print "@r\n";      # perl 1,2 1x,2x   chalk via B::SoN: 1,2 1,2

Also with a callee writing `$_` (`for (@a) { bump() }`). WRONG at 006b485
(stage 9a), 6fdb254 (9b) and id-collide alike: no scout ever caught it.

Why: the read flattens the literal (FromOptree's padav list read) unless the
slot or the literal is marked, and the walk marks it where it reaches the
write: after the read. The note's planned fix -- the header scanning for a
foreach whose iterator may be written -- could not be the whole of it: `$e
.= "x"` is a multiconcat with TARGMY and no padsv op, `$_ .= "x"` a gvsv
with no MOD flag, and the walk itself gets those writes right only by
learning (`_check_writes`). A slice store and a map's or grep's `$_` were
the same WRONG.

Fix, as Braun's other guesses are fixed: every list or void read of a
literal in a loop is recorded in each enclosing loop's frame; at sealing
(`_braun_seal`), a literal bound before the loop that the walk has since
marked is learned (`$hint->{mutated}`) and the sub walked again; the header
(`_braun_phis`) marks the learned slot, so the read goes through memory. A
second miss is refused by name. Test:
t/loop-header-marks-an-aggregate-its-body-writes-later.t.

Probes: docs/research/son-ir-audit-2026-11-19/probes/l (lw1-lw62 for this
class: 22 WRONG at d142906, 0 after). Probing next to it found a second
class, a foreach's write-back lost on a pass left early, closed on the same
branch: [[a-foreach-alias-write-is-a-store-where-it-stands]].

Related: [[a-loop-is-walked-once]], [[the-foreach-alias-is-a-reference]].
