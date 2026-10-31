sub g { my $k = shift; print "g$k"; return 1 } sub f { my $n = shift; if ($n > 1) { print "b" } return $n } print f(2) + g(7), "\n";
