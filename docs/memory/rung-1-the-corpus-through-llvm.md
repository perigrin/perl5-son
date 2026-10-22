---
name: rung-1-the-corpus-through-llvm
description: tools/corpus-llvm-roundtrip.pl runs the pvm corpus through chalk's LLVM backend and lli; 58/430 at chalk 5948f648, 14 wrong answers; the gap ranking says what to build next
metadata:
  type: project
---

Rung 1 of lowering perl's t/ to LLVM IR (perigrin, 2026-10-22). Each
corpus case goes through B::SoN's wire JSON, then chalk's
`Chalk::CodeGen::Pipeline->run_detail` (program mode, the
`main::__PROGRAM__` graph), then `lli`. Its stdout is compared with the
case's recorded output. Chalk is read at a pinned commit through
`git archive`, so only moving the pin moves the number.

Measured 2026-10-22: ROUNDTRIP 58, DIFFERS 10, LLI_FAIL 4, GAP 240,
LOAD_FAIL 118.
- The top causes: inlining a callee with effects (70), Call (33),
  Assign to a non-pad lhs (29).
- The loader doesn't know Exists (35), EntryWrite (21), Increment (19),
  PackageMark (19) or LocalAlias (12).
- Ratchet: corpus_llvm floor 58, corpus_llvm_wrong ceiling 14.

The machine environment:
- Chalk lives at /home/perigrin/dev/chalk, not ~/dev/chalk (HOME is
  /root), so set SON_CHALK.
- perl's t/ lives at /home/perigrin/dev/perl5/t, so set SON_PERL_T.
- lli on PATH is LLVM 18. Chalk's own son-e2e.t hard-codes llvm-15 and
  pvm paths, so it skips here.

**How to apply:** pick backend work from the top of the GAP_CAUSE and
LOAD_CAUSE lists. Treat a DIFFERS or LLI_FAIL before any gap, because a
wrong answer hides its cause.
