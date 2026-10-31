my $t = 0; sub f { my $n = shift; if ($n > 1) { return 10 } return 1 } for my $i (1..3) { $t = $t + f($i) } print "$t\n";
