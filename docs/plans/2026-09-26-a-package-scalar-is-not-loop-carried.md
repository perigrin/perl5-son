# A package scalar mutated in a loop body is not loop-carried

Status: **recorded, not fixed.** Measured 2026-09-26. Blocks perl's
`t/base/rs.t` (its non-VMS skip loop) and anything else that counts in a
package scalar across iterations.

## The shape

    our $n = 5;
    foreach $t ($n..$n + 3) {
        print "ok $t # skipped\n";
        $n++;
    }
    print "end $n\n";

    perl   ok 5 / ok 6 / ok 7 / ok 8 / end 9
    ours   ok 5 / ok 6 / ok 7 / ok 8 / end 6

The loop itself is right. `$n++` is wrong on every pass but the first: the
emission is

    my $inv7 = $stale7;          # hoisted, loop-invariant
    while (($inv32 > $phi12)) {
        ...
        $main::n = ($inv7 + 1);  # 5 + 1, every iteration
    }

so the store writes 6 four times.

## What the graph says

    7  EntryDef $main::n  in=[6]        the PRE-LOOP read
    9  Add(7, 1)                        the body's increment
    11 Loop
    29 Phi(4, 9) region=11              a Phi for $main::n EXISTS
    19 EntryWrite($main::n, 9, 6) ci=18 the body store, value = node 9

`_scout_mutated_targs` DOES detect the stash key -- Phi 29 is proof, and its
filter has no pad-only restriction. Two things are still wrong:

1. **Phi 29's init is Constant 5 (node 4), not the pre-loop read (node 7).**
2. **Nothing reads Phi 29.** The body's `Add` reads node 7 directly, so the
   increment is loop-invariant and the Phi is dead.

## Why the pad case works and this does not

A pad slot's read resolves through `$sim->lookup($targ)`, so re-pointing the
slot at the header Phi (`_patch_loop_phi`) is enough -- the next read finds the
Phi. A PACKAGE scalar's read does not go through the binding: the gvsv handler
builds a FRESH memory-pinned `EntryDef` whenever the name is in
`_package_scalars_written()`, precisely so a write in another sub is visible.
That bypass is right for the cross-sub case and wrong here: inside a loop the
value IS carried, and the carrier is the Phi.

So the two mechanisms disagree about who owns the current value of a written
package scalar -- the memory chain or the loop Phi -- and the loop's answer
never reaches the read.

## What a fix has to decide

The memory-pinned read is not simply wrong. `$n` can be changed by a call in
the body, and only a memory edge expresses that. The loop Phi and the memory
chain both have a claim, and the fix has to say which:

- **Phi over the memory version.** The memory Phi already exists
  (`$mem_phi`, patched at Phase 4). If the body's read were pinned to THAT
  rather than to the pre-loop version, it would observe the body's own store.
  This looks like the smaller change and keeps one owner (memory).
- **Phi over the value**, with the read resolving through the binding like a
  pad. Needs the gvsv bypass to make an exception for a key the enclosing loop
  has a Phi for, which is the disagreement written down rather than resolved.

Either way this is a producer change inside the loop machinery, and
[[removing-a-gap-can-create-a-miscompile]] applies: it currently produces a
SILENT WRONG ANSWER, so a partial fix can make things worse rather than refuse.

## Guard

`t/from-optree-a-package-scalar-is-loop-carried.t` does not exist yet. The
reduction above is the whole test; write it TODO-marked before attempting the
fix, so the wrong answer is recorded as a failing expectation rather than as
nothing.
