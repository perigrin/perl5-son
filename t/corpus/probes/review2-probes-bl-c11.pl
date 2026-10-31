sub f { my $a = shift; my $b = shift; if ($a > $b) { return $a } return $b } print f(3, 7), f(9, 2), "\n";
