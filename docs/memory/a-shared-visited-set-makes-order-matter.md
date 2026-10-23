---
name: a-shared-visited-set-makes-order-matter
description: gate3 flipped between 476 and 482 because Deparse's $used_in_arm walked every `if`'s arms into ONE visited set in hash order; an inner if walked first cut the outer walk short. Not load. Per-walk visited sets fixed it
metadata:
  type: feedback
---

gate3 reported 476 on some runs and 482 on others, always on the same six
LLVM tests. That happened even with the machine idle, so the earlier
"load" note was wrong. The chain:
- **Emission varied.** chalk-lib-roundtrip emitted 4 of 179 modules
  differently from run to run.
- **Deparse alone varied.** Rendering one fixed JSON under different
  PERL_HASH_SEEDs gave different Perl.
- **One check flipped.** Logging every check for the varying node
  showed only `$used_in_arm` changing between seeds.

The cause: the walk iterated `keys %reach` and marked each `if`'s arms
into one `%arm` set with `next if $arm{$id}++`. If an inner `if` was
walked first, the outer `if`'s walk stopped at the inner arm and never
reached what follows the inner join. Whether that use counted as in the
arm depended on hash order. Fixed by giving each `if`'s walk its own
visited set and taking the union of the arm sets.

Reproducing it took the real graph (chalk Precedence.pm, gzipped
fixture). Rendered alone, the sub was stable: hash order depends on
every hash used earlier in the process, so a small program does not
trigger it.

**How to apply:** a BFS that shares one visited set across several
roots computes "reachable from some root" correctly, but "each root's
own region" wrongly when the roots overlap. Any `keys %h` feeding a
decision is a determinism bug waiting. To test determinism, render one
fixed input under several seeds and require identical output. When
measurements flip between runs, check whether the emission itself
varies before blaming load.
