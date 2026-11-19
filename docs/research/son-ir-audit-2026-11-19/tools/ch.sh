#!/bin/sh
# ch.sh prog.pl -- B::SoN -> chalk (bson/llvm-corpus clone) -> lli, compared with perl
p=$(realpath "$1"); b=${p%.pl}
want=$(perl $p 2>&1)
perl -I/home/user/repo/lib -MO=-q,SoN,json,not_package=SoN $p > $b.json 2>/dev/null
why=$(cd /home/perigrin/dev/chalk && HOME=/home/runner PERL5_SON_LIB=/home/user/repo/lib timeout 120 perl -Ilib -It/lib /home/user/repo/tools/chalk-lower.pl $b.json $b.ll 2>&1)
if [ $? -ne 0 ]; then echo "$(basename $p): REFUSED $(echo "$why" | head -c 160)"; exit; fi
got=$(timeout 60 /usr/bin/lli $b.ll 2>&1 </dev/null)
[ "$got" = "$want" ] && echo "$(basename $p): ROUNDTRIP" || echo "$(basename $p): WRONG got=[$(echo "$got"|head -c 120)] want=[$want]"
