---
name: a-render-can-hang-without-refusing
description: Context.pm's lower_value (a hundred guarded returns) never finished rendering -- two exponential control walks; the census just sat there
metadata:
  type: feedback
---

Once the other refusals cleared, the census ran 11+ minutes on
LLVM::Context and never finished. A stack trace from SIGALRM showed
`_under_proj` (each Region re-walked every predecessor with a copied
seen-set) and `_arm_spine_pred` (asked again for every Phi of every
nested If). A dispatch of guarded returns doubled the work at each one:
time grew 2.5x per 4 returns.

Fix: memoize. `_under_proj` keeps a per-call memo at Regions.
`_arm_spine_pred` keeps a per-graph `%spine_memo`, saved and restored
in `_in_graph`. Forty returns now take 0.5 s and eighty take 3 s.

**Why:** walks written for one diamond meet chains of a hundred in real
modules. A hang looks like slowness, not a failure, so nothing reports
it.

**How to apply:** when a render runs past a few minutes, run it with
`$SIG{ALRM} = sub { Carp::confess }` and read the repeated frames.
Name the sub with a `$main::CUR = $name` probe. Pin a generated program
(N guarded returns) in a test under `alarm`, and time a few N first to
see the growth.
