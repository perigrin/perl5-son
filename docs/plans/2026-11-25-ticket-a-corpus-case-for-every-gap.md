# TICKET: a corpus case for every gap, and the deparser's 13 wrong answers

**Date:** 2026-11-25
**Status:** TICKET. Not started. Scheduled AFTER the memory-model goal is done
(perigrin, 2026-11-25).
**Rule it serves:** every edge or gap we run into becomes a corpus case
(docs/memory/every-edge-found-becomes-a-corpus-case.md).

## Where things stand

Branch `corpus-memory` added 58 memory-model cases in
`t/corpus/mdtest/pvm/memory-model.md`: 41 match perl, 17 are refused by name,
0 are wrong through chalk. The census floor rose from 426 to 467.

An inventory of every refusal site was made by `tools/gap-inventory.pl`, with
the table in `docs/plans/data/2026-11-25-gap-inventory.tsv`. Regenerate it
before starting, because the code will have moved on. The counts:

| Where | Sites |
|---|---|
| Producer (B::SoN), `GAP:` | 286 |
| Deparser | 118 |
| chalk, `GAP:` | 97 |
| chalk T2, "out of its slices" | 378 |
| **Total** | **879** (733 distinct messages) |

- 15 sites already have a corpus case. That is a lower bound, because the
  census reports only a case's first refusal.
- 648 have none; 91 of those have an audit probe that triggers them.
- 216 build their message at run time, so text matching cannot find them.

## Work

1. **The 91 with a probe:** add one corpus case each, taking the program from
   the probe and the expected output from perl.
2. **The other 557:** sort them into sites a program can reach and internal
   checks no program can reach.
   - Reachable: write a minimal program, check it against perl, and add it as
     a refused case.
   - Unreachable: decide for each whether it should become a "malformed
     wire" error or an assertion, or be deleted.
   - The 216 run-time messages: give each a stable prefix the guard test can
     match.
3. **A guard test** that fails when a refusal message in either repo has no
   corpus case.
   - Producer messages: check offline, from the `refused:` lists in the IR
     blocks.
   - chalk messages: these need census output, so run on request, like the
     other slow ratchets.
   - Hold the remainder by name, and drive that list to zero.
4. **The deparser's 13 wrong answers** (`SoN::Deparse`, found by the new
   corpus cases). Fix each, or refuse it by name:
   - it writes `local` as save, store and restore, which breaks `$_[N]` and
     references to the saved scalar;
   - `$1` is not restored at a block's end;
   - DESTROY;
   - one loop where a read misses the stores from earlier passes.
   
   Also add a gate for deparser DIFFERS. Today no gate counts them, which is
   why these were missed.
5. **chalk's corpus.** The corpus gate (222) runs chalk's own
   `t/corpus/mdtest`, not the producer's. Decide whether the memory-model
   cases should be added there too, so the corpus gate holds them.
6. **Loose ends:**
   - `corpus_llvm` (412) in `t/roundtrip-ratchet.t` is pinned to chalk
     287e5da1. Re-measure it at the current chalk.
   - `t/corpus-ir-blocks.t` reports 650 drifted blocks, mostly random tmp
     paths. Refill them in a commit of their own, and make the paths stable.
   - Audit-2 class K9 needs a corpus case with a second module file; the
     corpus has no multi-file case format yet.

## Done means

- The guard test passes with no held names.
- The deparser's DIFFERS are gated at 0.
- Every case's expected output comes from perl.
