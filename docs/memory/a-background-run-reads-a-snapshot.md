---
name: a-background-run-reads-a-snapshot
description: a census or gate run reads lib/ for its whole length; edit only a separate copy meanwhile, and kill runs by PID, never by a pattern your own shell also contains
metadata:
  type: feedback
---

Four runs were spoiled in one session: lib/ edited while a census read it
(twice), a scratch experiment written into the very `exp/lib` copy the
running comparison used, and `pgrep -f "bisect.pl" | xargs kill` killing
the shell that ran it -- the command line contained the pattern -- so the
steps after it silently never ran and the next run used a stale snapshot.

**Why:** the census emits module by module over ~15 minutes; any edit in
that window mixes two versions into one measurement. `pkill -f` and
`pgrep -f` match the invoking shell's own argv.

**How to apply:** snapshot lib/ (and tools/, which FindBin resolves
through symlinks) into one directory per running job; experiment in
another (`exp2`, `rt_exp2.sh`). Kill by listing `ps -eo pid,args`,
filtering out `grep`, and passing PIDs. After any kill, check that the
steps meant to follow actually ran (exit 144 means the shell died).
