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
