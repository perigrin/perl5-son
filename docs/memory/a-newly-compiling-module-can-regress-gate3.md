---
name: a-newly-compiling-module-can-regress-gate3
description: A fix that lets one more chalk module compile can drop gate 3 sharply -- the module is overlaid and exposes an older miscompile
metadata:
  node_type: memory
  type: feedback
  originSessionId: c7427872-965a-4f72-9cbb-d235a4680e53
  modified: 2026-10-02T18:50:55.076Z
---

Gate 3 overlays every chalk module that compiles cleanly. A fix that makes one MORE module compile puts that module into the overlay, and any miscompile already latent in it goes live. On 2026-10-02 signature reconstruction let Chalk::MOP compile (its `%opts` parameter had refused); MOP's `return values %classes` hit an old stamp bug (want 0 read as scalar), and gate 3 fell from 531 to 370 because nearly every test walks the MOP.

**Why:** COMPILES rising and SAME falling look contradictory until you check which modules entered the overlay. The regression is not in the change just made.

**How to apply:** When SAME drops after a COMPILES rise, diff compiles.txt between the two emissions first and look at the new modules' emissions; sample ~60 tests with a rerun script rather than waiting for a full gate run. Related: [[compiling-is-not-running]], [[removing-a-gap-can-create-a-miscompile]].
