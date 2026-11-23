---
name: pending-bug-foreach-write-back-later-in-a-loop-body
description: "OPEN (found 2026-11-23, not Braun's: WRONG at 006b485 too): a foreach that writes its iterator later in a loop body is not seen by a list read of the array earlier in the body on the next pass -- `1,2 1,2` for perl's `1,2 1x,2x`"
metadata:
  type: project
---

OPEN. Found while accounting for the 9b proof's rows (baseline section 19).

    my @a = (1,2); my @r;
    for my $i (1..2) { push @r, join(",", @a); for (@a) { $_ .= "x" } }
    print "@r\n";      # perl 1,2 1x,2x   chalk via B::SoN: 1,2 1,2

Also with a callee writing `$_` (`for (@a) { bump() }`). WRONG at 006b485
(stage 9a), 6fdb254 (9b) and id-collide alike: no scout ever caught it.

Why: the read flattens the literal (FromOptree's padav list read) unless the
slot is marked; the in-loop guard marks it when `$MUTATED_SLOTS` has the
slot, and `_mutated_aggregate_slots` does not count a foreach whose iterator
is written (only one whose iterator is a call's argument). The foreach marks
the literal (%MUTATED_LITERALS) where it is walked: after the read.

Fix when next: the Braun header (`_braun_phis`) marks the slot of a foreach
in its cycle whose iterator may be written (`_iterator_may_be_written`), as
it marks an array passed to a call; test first, through chalk.

Related: [[a-loop-is-walked-once]], [[the-foreach-alias-is-a-reference]].
