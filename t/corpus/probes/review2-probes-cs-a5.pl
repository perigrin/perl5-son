sub f { my $n = shift; my $s = 0; for my $i (1..$n) { $s = $s + $i } return $s } my $t = 0; for my $j (1..3) { $t = $t + f($j) } print "$t\n";
