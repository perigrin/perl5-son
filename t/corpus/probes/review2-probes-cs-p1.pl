sub f { my $n = shift; my $s = "x"; if ($n > 1) { my $t = "big"; print $t } print "$s$n\n"; return 0 }
my $a = 1.5; my $b = "q"; my $c = 7; my $d = "zz";
f(1); f(2); print "$a$b$c$d\n";
