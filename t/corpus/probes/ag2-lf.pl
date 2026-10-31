sub f { my $s; for my $x (@_) { $s = $x } return $s } print f(3, 4, 5), "\n";
