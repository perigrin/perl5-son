sub f { my $n = shift; my $s = 0; for my $i (1 .. 10) { last if $i > $n; $s = $s + $i } return $s } print f(3), f(0), "\n";
