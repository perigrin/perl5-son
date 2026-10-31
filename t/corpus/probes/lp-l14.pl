sub f { my $n = shift; my $s = 0; for my $i (1 .. 5) { return $s if $i > $n; $s = $s + $i } return -1 } print f(2), " ", f(9), "\n";
