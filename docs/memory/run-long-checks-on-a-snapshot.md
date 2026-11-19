---
name: run-long-checks-on-a-snapshot
description: "A suite, census or verifier run that reads the working tree while it is being edited reports a mix of two producers. Copy the tree, run there, keep editing"
metadata:
  type: feedback
---

The first census of the `placement` work said ROUNDTRIP 253, LOAD_FAIL 174
("no program graph with a return"). Nothing was broken: a rewrite of
`lib/SoN/FromOptree.pm` landed while the census was a minute in, and half its
cases were compiled by a file that called a sub not yet defined.

**Why:** the suite takes 9 minutes, the LLVM census 5, the verifier 4, the
deparse census 3. Waiting on each blocks the work; running them against the
live tree lies.

**How to apply:** `tar` the worktree (without `.git`) into a scratch
directory and run there -- every tool finds the producer through
`$FindBin::Bin/../lib` or `-l`. Set `PERL5_SON_LIB` to the copy's lib for
chalk's tools. Name the copy after what it holds; the copies also make a
bisect cheap (`prove` one test in each).

- A producer change belongs in a commit only after the copy that holds it
  has run. I committed W1 before its suite finished, and the suite then
  found five deparser failures: a second commit, and a third for the fix's
  own regression.
- **Green probes are not a green suite.** With all 436 probes unchanged, the
  suite of the same tree failed 11 files: a refusal that fired on ordinary
  code, a restore the deparser read as a block's end, two tests asserting
  the old saved value. Run the suite before the commit message is written.
- chalk's corpus gate (`t/bootstrap/corpus/son-corpus-wide.t`) names
  `/usr/lib/llvm-15/bin/lli`, which rejects `ptr`: run as is it reports
  gate-green=0 and REWRITES `paad/worklist.json` in the chalk checkout. Run
  it in a `git archive` copy of chalk with the path swapped for /usr/bin/lli.
- `t/corpus-llvm-roundtrip.t` fails 5 of 13 at d0b248e in this environment
  (before any of this work); do not chase it.

Related: [[verify-the-harness-before-reading-its-output]],
[[the-wire-verifier-and-its-ratchet]].
