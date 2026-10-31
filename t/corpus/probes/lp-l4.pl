sub f { my $n = shift; my $s = 0; while ($s < $n) { if ($s > 1) { $s = $s + 2 } else { $s = $s + 1 } } return $s } print f(6), "\n";
