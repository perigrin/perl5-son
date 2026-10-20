---
name: make-the-guard-fail-on-purpose
description: The only property separating a real guard from a decorative one is whether anyone has made it fail deliberately
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 03347934-6f4e-47de-b925-06eaae0f6389
  modified: 2026-09-26T18:40:39.993Z
---

A guard that has never FAILED ON PURPOSE is not known to be a guard. Break it
deliberately, watch it fail, put it back. It costs one command and it is the
only check that distinguishes a real ratchet from a decorative one.

Five instruments in one session (2026-09-26), four found that day, all of them
passing and all measuring something adjacent to their question:

- **My two censuses** were scripts in `tools/` that NO TEST INVOKED. The goal's
  numbers held only while I remembered to run them by hand.
- **pvm's corpus-ratchet header** could have said 999 cases and passed.
- **pvm's `t1canon` ratchet** recorded 46 canon-broken files AS its baseline --
  measuring the symptom as the expected state, for weeks.
- **pvm's `lintOps`** parses `B::Concise`'s rendered TEXT, so it sees op names
  and not flags: an awk-mode `split` and a pattern `split` satisfy the same
  budget, and `local *v` differs from `*v` only by `OPpLVAL_INTRO`.
- **pvm's 620-file goal** was gated by nothing in CI: `parse.Parse(src []byte)`
  takes no loader, so every baseline was blind to the resolution the goal
  depends on. It moved 185 -> 278 with all six ratchets byte-identical.

**Why:** a guard is written when the thing it guards is already correct, so it
passes on the first run and there is no moment where the author sees it work.
Every one of these passed continuously while measuring the wrong quantity.

**How to apply:** when you add a ratchet, floor or invariant, immediately
falsify it.

    # raise the floor above the real number, run, confirm exit 1, put it back
    corpus => 999,      ->  `ROUNDTRIP 154 >= floor 999`  FAILED  exit 1

And check the DENOMINATOR before the floor. A census that parsed nothing reports
0 of everything and passes a floor by vacuous truth --
[[verify-the-harness-before-reading-its-output]] applied to the guard rather
than the measurement.

A skip must say how to run it. An opt-in guard that skips silently is another
unchecked instrument.

Related: [[a-refusal-test-that-only-translates]],
[[clean-counts-cannot-measure-progress]],
[[a-guard-can-measure-the-wrong-quantity]]
