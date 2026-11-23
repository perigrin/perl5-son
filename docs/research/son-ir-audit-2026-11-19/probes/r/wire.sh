#!/bin/bash
perl -I/home/user/repo/lib -MO=-q,SoN,json,not_package=SoN "$1" 2>/dev/null | perl -MJSON::PP -0ne '$w=decode_json($_); for $g (sort keys $w->{methods}->%*){print "== $g\n"; for $n ($w->{methods}{$g}{nodes}->@*){ my %h=%$n; my $id=delete $h{id}; my $op=delete $h{op}; print "$id $op ", JSON::PP->new->canonical->encode(\%h),"\n"}}'
