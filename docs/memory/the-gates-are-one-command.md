---
name: the-gates-are-one-command
description: "tools/gates.sh (both repos) runs the two suites, the census, chalk's corpus gate, the audit probes and the verifier ratchet on snapshots, resumably, one line each. What it had to learn: chalk's snapshot must be a git repo, the suite rewrites paad/worklist.json, the ratchet names a commit"
metadata:
  type: project
---

Wire v2 plan, stage 0 (branch `v2-s01`, 2026-11-20). `tools/gates.sh` in the
producer is the implementation; chalk's `tools/gates.sh` execs it with
`--chalk` its own checkout (found through `PERL5_SON_LIB`).

    HOME=/home/runner nohup tools/gates.sh --chalk /path/to/chalk --out DIR > DIR.log 2>&1 &
    tools/gates.sh --summary --out DIR      # any time; exit 0 only when all PASS
    tools/gates.sh --only census,probes --out DIR

Run the same command again after a kill or a container restart: finished
test files and finished gates are not run again. A changed tree needs a new
DIR (the snapshot is taken once).

**What it had to learn:**

- **chalk's snapshot is committed into a repository of its own.** The census
  reads chalk through `git archive COMMIT` from a directory with a `.git`
  DIRECTORY; a worktree has a `.git` file, and a dirty tree has no commit.
  `git init; git add -A; git commit` in the copy gives both, and
  `--commit HEAD` reads it.
- **chalk's suite rewrites `paad/worklist.json`.** Not only
  `son-corpus-wide.t`: a test that runs the corpus gate through a harness
  writes it too. In a snapshot that is harmless, but the gate's "worklist
  untouched" line read MODIFIED an hour after it had read untouched.
  `CHALK_WORKLIST_OUT` is exported for everything now, and the answer is
  recorded when the corpus gate ends, not when the summary is printed.
- **A check read at summary time can change under you.** Same lesson, stated
  generally: record a gate's verdict inputs when the gate finishes.
- **The ratchet's chalk rows name a commit** (`# chalk at SHA` in the
  baseline) and the test skips them when chalk is elsewhere. A snapshot has
  no such commit, so the test takes `SON_CHALK_AT`; the gate reports MISS,
  not PASS, when the rows were not compared. Every chalk commit therefore
  needs the baseline's line moved (and the rows re-counted if chalk's lib
  changed).
- **Do not subtract the side gates' processes from the suite's workers for
  the whole run.** The first version gave the suites JOBS - 3; with 4 cores
  that was one worker for 741 files, long after the side gates had ended.
- **Three files are left out of the suites** because they are gates of their
  own (`son-corpus-wide.t`, `audit-probes.t`, `wire-verify-ratchet.t`). The
  suite lines say how many files they ran.
- **Background jobs that share the machine double each other's time.** With
  the suite (4 workers), a chalk-lib verify (2) and a measurement (2) on 4
  cores the load was 11 and the census took 3 times its 5 minutes. Queue,
  do not stack.
- `tools/wire-verify.pl --jobs N` compiles wires in parallel (the verifying
  stays one process); `SON_WIRE_JOBS` passes it through the ratchet test.

Related: [[run-long-checks-on-a-snapshot]],
[[the-wire-verifier-and-its-ratchet]].
