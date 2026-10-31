sub f { my $n = shift; my $s = 0; if ($n > 2) { for my $i (1 .. $n) { $s = $s + $i } } return $s } print f(3), f(1), "\n";
