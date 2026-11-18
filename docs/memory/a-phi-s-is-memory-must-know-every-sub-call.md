---
name: a-phi-s-is-memory-must-know-every-sub-call
description: T2's stale read after eval { $code->() } was T1's Phi::is_memory missing indirect calls; and a repro that "does not reproduce" needs its other half
metadata:
  node_type: memory
  type: feedback
  modified: 2026-11-18T00:00:00.000Z
---

The silent wrong answer "a package scalar written through `$code->()` inside
`eval {}` is read stale after it" (Test::Chalk's subtest in an eval) was not
in Target/LLVM at all. `Chalk::IR::Node::Phi::is_memory` counted a Call input
as a memory version only for `direct|method`, so the eval's join Region's
memory Phi (B::SoN flagged it `memory: true`!) read as a VALUE phi. T2's
close_eval pushes `$r->memory_phis` onto `passed`; with none, no store ran
`reads_before` for that version, and the read was built at its first use --
after the next store (`$C = $save`). Fix: `$in->is_sub_call` (adds indirect).
Test: t/bootstrap/ir/llvm-a-package-scalar-a-code-ref-call-wrote-in-an-eval.t.

**Why:** a predicate that lists dispatch kinds by hand drifts from the one
that defines them (Call::is_sub_call). Ask the defining predicate.

**How to apply:**
- The recorded one-line repro (`... eval { $code->(); 1 }; print $C + 0`)
  ROUNDTRIPPED on today's head; only adding the store after the read
  (`my $n = $C + 0; $C = $save`) reproduced it. A stale read needs a later
  store to be stale against -- minimize keeping the store.
- Find it by instrumenting reads_before (which versions, which readers) and
  close_eval (does `memory_phis` find the Phi?), not by reading the .ll alone.
- Don't run a long probe test while still editing t/lib/Test/Chalk.pm: each
  probe recompiles it from disk, so the run mixes versions.
