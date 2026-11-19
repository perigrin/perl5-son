#!/bin/sh
# gen_chalklib.sh -- B::SoN wires of a sample of chalk's own lib modules (read-only), into audit/chalklib/
ulimit -v 4000000
cd /home/perigrin/dev/chalk
i=0
for m in lib/Chalk/IR/*.pm lib/Chalk/IR/Transform/*.pm lib/Chalk/MOP/*.pm lib/Chalk/Target/LLVM/Lower.pm lib/Chalk/Target/LLVM/Printer.pm lib/Chalk/Target/LLVM/Builder/Args.pm lib/Chalk/Target/LLVM/Builder/Variables.pm lib/Chalk/Target/LLVM/Builder/Regex.pm lib/Chalk/Grammar/*.pm; do
  i=$((i+1)); n=$(printf '%03d' $i)
  echo "$m" > /tmp/claude-0/audit/chalklib/$n.file
  HOME=/home/runner timeout 300 perl -I/home/user/repo/lib -Ilib -MO=-q,SoN,json,not_package=SoN $m > /tmp/claude-0/audit/chalklib/$n.json 2> /tmp/claude-0/audit/chalklib/$n.err
done
echo "done $i"
