---
name: chalk-rows-are-held-per-graph
description: perigrin 2026-11-21 -- the verifier ratchet holds chalk's lib per graph (a recorded graph may not rise, a new one is printed); a dropped wire fails; its first catch was a v2 copy with its memory as an input
metadata:
  type: project
---

perigrin's decision at the stage 2+3 integration: chalk's lib changes in every
chalk-side stage, so its totals moved with graphs the producer had never
seen. t/data/wire-verify-chalk-graphs.tsv records each graph's count per rule
(the most one wire counts; a file graph is named by its wire), and
t/wire-verify-ratchet.t fails only when a recorded graph rises. A graph not
in the record is printed. corpus and probes stay totals. Re-record at merge.

A dropped wire fails too: tools/wire-verify.pl counts a compile that timed
out, was killed or wrote no JSON as #dropped, and does not cache it. A
program perl rejects (exit 255) keeps the wire B::SoN writes of what
compiled, as it always did: chalk's Target/LLVM/Node/*.pm and probe p/st3
are such programs. (An exit-status-only rule dropped them: 10 chalk wires,
1147 graphs.)

**Why:** totals over another repository's moving lib hid real rises and
showed false ones; a timed-out wire took its rows out in silence.

**How to apply:** a ROSE line names graph and rule; a rise in a graph a chalk
stage edited can still be the producer's. The first one was: chalk's
array_stmt dropped a `pop` after `my @in = $s->inputs->@*`, and the copy
B::SoN remakes for that `my @in` carried its memory as a v1 positional input
on wire v2 (fixed 77c664b; it also cured pvm 235/236 wrong under wire=2).
Falsify the record after re-recording: lower one graph by one, expect ROSE.
