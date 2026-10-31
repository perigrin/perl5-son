sub f { my $n = shift; if ($n > 1) { print "F" } return $n } sub g { my $n = shift; if ($n > 1) { print "G" } return $n } print f(2) + g(3), "\n";
