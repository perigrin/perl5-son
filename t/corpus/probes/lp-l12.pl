sub f { my $n = shift; my $s = 0; for my $i (1 .. $n) { for my $j (1 .. $i) { if ($j % 2) { $s = $s + 1 } } } return $s } print f(3), "\n";
