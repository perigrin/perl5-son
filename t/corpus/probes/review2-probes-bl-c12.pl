sub f { my $n = shift; my $s = 0; while ($n > 0) { $s = $s + $n; $n = $n - 1 } return $s } print f(4), "\n";
