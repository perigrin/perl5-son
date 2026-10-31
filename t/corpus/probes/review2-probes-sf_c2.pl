sub f { my $n = shift; if ($n > 1) { print "F" } return $n } sub g { return 5 } print g() + f(1), "\n";
