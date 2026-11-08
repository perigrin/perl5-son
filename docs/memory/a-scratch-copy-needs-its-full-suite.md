---
name: A scratch copy needs its full suite before it is ported
description: 2026-11-08 -- scratch B::SoN work passed its own and the touched tests, was ported and pushed, and broke 19 deparse tests; the full suite on the scratch copy had been started, then killed as stale.
type: feedback
---
Work done in a scratch copy (to keep a running census honest) was checked
only against the tests it touched, then copied over and pushed. The full
B::SoN suite on that copy had been started, superseded, and killed -- never
rerun. The live run found 19 failures: pinning every read through a
reference reordered foreach aliases, `local` on an element and compound
stores; an element autovivify inside a loop body tripped the deparser.

**Why:** a graph-shape change (a pin, a new store) reaches every walk that
makes that node, not just the probes that motivated it.
**How to apply:** before porting a scratch B::SoN, run its whole `t/` (the
xargs -P 3 form) to completion; a killed run is no run. If the census must not
be disturbed, wait for it rather than skipping the suite.

**And the probe set lives partly at the scratchpad ROOT** (`allprobes.txt`
lists 21 `$S/*.pl`). Session probes written there with short names
(sh1, sh2, lp1, lp3, lv1, lv2 -- 2026-11-08) overwrote baseline probes; the
originals are lost (sh1 was a baseline wrong answer, a 2**53+1 integer kept as
a double -- the class k07/h16 still cover). New probes go in a subdirectory
(`$S/mine/`), never the root. The wrong-probe baseline after this is
`$S/w362-baseline` (w299c, sh1 out, lv1 in -- lv1 is the pre-existing Context
push-in-a-loop miscompile in wrong-answers-2026-11-08.md).
