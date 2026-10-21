---
name: a-dead-node-still-rides-in
description: graph membership walks consumers, so a node nothing reads is still serialized and a deparser pass can spell it; and a loop that moves memory needs a header memory Phi for its exit
metadata:
  type: feedback
---

Two INVALID modules surfaced once more of chalk translated. Both causes
were pre-existing on the base:

- `for my $oh ($chart[$pos]->@*) { $n++ }` (iterator never read).
  `_translate_foreach_array` always builds `$elem`, the per-pass copy.
  Unread, it still hung off its inputs' consumer lists, so the serializer
  emitted it. The stale-read pass then spelled `$staleN = $a[$phi]` ahead
  of the loop that declares `$phi` (Earley, `Global symbol "$phi931"`).
  Fix: after the body, unhook an unread `$elem`
  (`remove_consumer` on its inputs), as `_split_aggregate_phi` already
  does. Also don't build the alias-by-reference when the body never
  names the iterator.
- A body whose memory moved without a header memory Phi
  (`_body_stores_memory` missed a `push` in an elsif arm) left the
  post-loop memory at the body's last branch join. A demoted `$ctx` read
  after the loop took that join, and `my @walk = ($ctx)` was declared
  inside the loop (Perl::Actions::Block, `Global symbol "@walk"`). Fix:
  build the header Phi late, from the pre-body memory and the body's last
  version. The body's own reads keep the entry version, as before.

**Why:** a node with no readers is still a node to every consumer-walk.
And the exit edge leaves from the header, so its memory must be a header
Phi.

**How to apply:** for an INVALID "Global symbol" in an emission, look up
the named node's users first (`nd.pl`). `users=[]` means it is dead
weight, not a placement bug. `reduce_inv.pl` (scratchpad) reduces on
`perl -c` of the emission.
