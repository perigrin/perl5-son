#!/bin/bash
# usage: run_old.sh TAG files...  (TAG: s10 = first goal audit heads; s6, s8 ...)
t=$1; shift
cd /tmp/claude-0/wt/$t-c && . /tmp/claude-0/-home-user-repo/adb6f1fb-b446-5864-9f34-e919755b5de6/scratchpad/s9/env.sh; export PERL5_SON_LIB=/tmp/claude-0/wt/$t-p/lib HOME=/home/runner; ulimit -v 4000000
perl -Ilib -It/lib /tmp/claude-0/-home-user-repo/adb6f1fb-b446-5864-9f34-e919755b5de6/scratchpad/s9/run1.pl "$@"
