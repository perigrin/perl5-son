sub f { my $n = shift; my $s = 0; for my $i (1 .. $n) { if ($i % 2) { $s = $s + $i } } return $s * 2 } print f(3), "\n";
