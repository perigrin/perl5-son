---
name: a-statement-boundary-clears-the-stack
description: three defects of one kind -- a do block's value, a `//` die arm's fallback, and a list assign each read an earlier statement's leftover on the sim stack
metadata:
  type: feedback
---

The sim stack is not cleared between statements. Void statements leave
values there: a list assign's Assign, a `my $i = 0` store. Three
consumers read that residue as their own value:

- `E // die`: a fallback that pushed nothing popped the residue.
- `my %I = do { my $i = 0; map {...} @F }`: the do block's value began
  with the 0. The loop walker trimmed at a `nextstate` inside a block;
  the main walk did not.
- A merge's stack Phi took two residues.

Fixes: compare against the depth taken at the snapshot or at the block
entry, never against 0. The main walk now trims to the enclosing
`enter`'s depth at each `nextstate`, as the loop walker does.

**How to apply:** when a value is "whatever is on the stack", ask what
the depth was when the construct began. When two walkers handle the
same op, check both: a fix in one leaves the other open.
