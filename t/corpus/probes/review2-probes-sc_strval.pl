sub f { my $n = shift; my $s = "x"; if ($n) { $s = "y" } return $s } print f(1), f(0), "\n";
