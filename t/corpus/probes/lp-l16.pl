sub f { my $n = shift; my $s = 0; for my $i (1 .. $n) { if ($i % 2) { $s = $s + $i } } return $s } for my $k (1 .. 3) { print f($k) } print "\n";
