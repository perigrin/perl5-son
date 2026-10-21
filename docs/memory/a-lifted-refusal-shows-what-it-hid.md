---
name: a-lifted-refusal-shows-what-it-hid
description: turning the in-loop stale element-read refusal into a per-pass binding exposed alias-vs-copy, refalias and tie cases the refusal had been covering; each needed its own guard
metadata:
  type: feedback
---

The deparser refused "an element read in a loop spelled after a store".
Binding the read to a `$staleN` at the top of the body (or right after
its own version) fixed chalk's LLVM::Context, and about forty tests that
expected the refusal started rendering. Most of them were right. Three
were silently wrong:

- `for my $x (@a) { $x .= "y"; $a[0] = "q"; $s .= $x }` gave `1y` for
  `q`. The IR carries the alias as a value written back at the end of
  the pass, so it can't see the other store. Guard: an alias read (one
  that feeds a write-back, or the foreach's own read by its counter)
  binds only when every store in the pass is its own write-back.
- `\$h{b} = \$h{a}` arrives as a whole-hash store. Guard: the aggregate
  must be plain through its merges (only Subscript, Count, Phi and
  ListAppend consumers, no Ref of an element, not `shared`).
- A `while ($a[0] < 3)` test read the same node and got the pass
  before's temporary. Guard: every control consumer lies in the body.

**Why:** a refusal records an unknown, not a known-bad shape. Removing
it lets every shape it covered through, including the ones nobody named.

**How to apply:** after lifting a refusal, run every test that expected
it. For each case that now renders, compare its output with perl
(`refcheck2.pl` handles `refuses`/`render_refuses` with `q{}`, `q()` and
heredocs; `$ci . q{...}` sources need a manual run). Convert only the
ones that round-trip, and add a test for each guard that keeps the rest
refused.
