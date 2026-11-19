#!/bin/sh
# runp.sh files... -- run ch.sh on each probe, sequentially, under a memory limit
ulimit -v 4000000
for f in "$@"; do sh /tmp/claude-0/audit/ch.sh "$f"; done
