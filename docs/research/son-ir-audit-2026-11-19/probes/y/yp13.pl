my %h=(a=>1,b=>2); sub z { $h{b}=7; $h{a}=7 } my $s=0; for my $v (values %h) { $s += $v; z() } print "$s\n";
