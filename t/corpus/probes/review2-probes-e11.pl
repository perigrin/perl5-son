sub g { my $n = shift; if ($n) { print "g" } return 2 } sub f { my $n = shift; if ($n) { print "f" } return g($n) } print f(1), "\n";
