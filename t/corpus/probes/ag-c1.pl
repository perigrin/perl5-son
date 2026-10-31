sub f { my $s = 0; for my $x (@_) { $s = $s + $x } return $s } print f(1, 2, 3), "\n";
