---
name: session-bug-interned-pinned-nodes
description: A SILENT WRONG ANSWER this session introduced (chalk 43ba40ea, live until fixed): foreach over @_ with `next` + push returned an empty list -- the JSON loader interned two pinned nodes of one content, the second pin overwrote the first, the loop body was dropped; found by a probe, not the census
metadata:
  type: project
---

**Symptom:** `sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o,
$x } join ",", @o }` printed "" for perl's "a,c"; `scalar(@o)` gave 0.
Refused at the baseline; WRONG from chalk 43ba40ea ("reads frozen where
their memory is"), which turned the old refusal into a lowering -- through
every pin from 225 to 234. DIFFERS stayed 0: no corpus case has the shape.
A probe for 097's cause found it.

**Why:** B::SoN reads a foreach-over-@_ `$x` as `exists $_[$i] ? $$alias :
$_[$i]` at each use. Two such reads (the `next if` test, the push's
argument) have the same CONTENT and differ only in control_in. The JSON
loader's factory interned them to one node; `set_control_in` for the
second overwrote the first's pin, which then named the If's own then-Proj.
The arm walk found a chain looping through its own If, owned nothing, and
the loop body (the if, the push) was dropped -- no refusal.

**Fix (chalk IR/Serialize/JSON.pm):** a wire node with a control_in that
interns to a node already pinned elsewhere is built with `make_unique`.

**Lessons:**
- control_in is outside content_hash by design ("a per-use decoration"),
  so ANY interned node that is pinned can be pinned twice. The loader is
  where the wire's distinct ids are still known -- keep them distinct there.
- A whole statement dropped is the worst miscompile: no invalid IR, no
  refusal. Probes must vary the SHAPE around a working case (`next` +
  push in a sub over @_), not just its values.
- Bisect with `git worktree add` per commit and one JSON: minutes, and it
  named the commit.
