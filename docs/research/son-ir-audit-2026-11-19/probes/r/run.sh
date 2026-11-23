#!/bin/bash
# usage: run.sh files... ; prints verdict per probe
cd /home/perigrin/dev/chalk && . /tmp/claude-0/-home-user-repo/adb6f1fb-b446-5864-9f34-e919755b5de6/scratchpad/s9/env.sh; export PERL5_SON_LIB=/home/user/repo/lib HOME=/home/runner; ulimit -v 4000000
perl -Ilib -It/lib /tmp/claude-0/-home-user-repo/adb6f1fb-b446-5864-9f34-e919755b5de6/scratchpad/s9/run1.pl "$@"
