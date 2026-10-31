sub f { my $n = shift; if ($n > 1) { print "F" } return 0 } sub g { my $n = shift; return $n } print g(5) > 1 ? "y" : "n"; f(1); print "\n";
