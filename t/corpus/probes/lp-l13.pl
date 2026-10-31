sub f { my $n = shift; my $s = 0; if ($n) { for my $i (1 .. 3) { if ($i > 1) { $s = $s + $i } } } return $s } print f(1), f(0), "\n";
