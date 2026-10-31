sub f { my $n = shift; if ($n > 1) { print "F" } return $n } sub g { my $n = shift; return $n } print g(5) + f(1), "\n";
