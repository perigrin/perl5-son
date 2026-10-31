sub f { for my $x (@_) { return $x if $x > 1 } return 0 } print f(1, 5, 7), "\n";
