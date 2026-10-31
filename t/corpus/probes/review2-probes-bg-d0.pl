 sub f { my $n = shift; my $y = $n * 2; my $z = 3; for my $i (1..$n) { $z = $z + $y } if ($n > 1) { $y = $z } return $y } print "|", f(2), "|", f(1), "\n";
