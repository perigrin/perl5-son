---
name: perl-blocks-split-loops-vs-callees
description: Perl's block-taking constructs split two ways in the IR -- loops vs callees -- and which is which
metadata:
  type: project
---

perigrin's classification of Perl's nameless blocks, confirmed by measuring the
optrees (2026-09-01):

- **LOOPS** (carry a loop op, lower as counted loops): `map`, `grep`, bare
  blocks, postfix `for`. map/grep carry mapwhile/grepwhile exactly as `while`
  carries enterloop/leaveloop.
- **CALLEES** (no loop op, need a calling convention): `sort`'s comparator,
  anonymous subrefs. The tell is `sort &foo @list` -- a comparator can be a
  named sub, so it is a callee.

**Why:** the two kinds need different IR treatment, and conflating them sent a
wrong answer to chalk once already ("sort's block is the same calling
convention as map's" -- it is a different KIND, not a different extraction).
These are nameless blocks and Perl lets you put a block almost anywhere, so
there is no single right lowering for all of them.

**How to apply:** lower a LOOP with the counted-loop machinery -- map/grep only
needed `ListAppend` on top of it, because their output length is not their
input length. A CALLEE needs block-as-graph plus closure capture, which is one
problem living in `anoncode` alone: an inline sort comparator reads outer
lexicals as plain `padsv`, not as capture.

See [[one-operator-five-declaration-sites]] for the IR ergonomics cost of
adding vocabulary like ListAppend.
