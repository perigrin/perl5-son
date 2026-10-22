---
name: gate3-under-load-drops-files
description: gate3 run while another 8-job census ran reported SAME 476 of 482; alone it was 482 twice; never overlap the ratchet with other heavy jobs
metadata:
  type: feedback
---

A SON_RATCHET=1 run that overlapped corpus-llvm-roundtrip.pl (8
parallel jobs) reported gate3 SAME 476, DIFFERS 6. gate3 alone and the
fullcmp comparison both gave 482 of 482, and a clean ratchet rerun with
the machine otherwise idle passed at 482. Some chalk tests are
timing-sensitive, and per-file results shift when the box is loaded.

**How to apply:** run the ratchet, gate3 and fullcmp with nothing else
heavy running. When a SAME count drops, rerun gate3 alone with -v
before chasing the drop as a regression.
