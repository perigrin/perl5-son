sub f { my $n = shift; my $y = 1; if ($n > 1) { $y = 3 } return $y } my $a = 10; my $b = 20; my $c = 30; my $d = 40; if ($a) { $b = 21 } print f(2), f(1), " $a $b $c $d\n";
