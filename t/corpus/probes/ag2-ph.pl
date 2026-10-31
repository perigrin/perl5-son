sub f { my $s = 7; for my $x (@_) { $s = $x if $x > 3 } return $s } print f(3, 4, 2), f(1), "\n";
