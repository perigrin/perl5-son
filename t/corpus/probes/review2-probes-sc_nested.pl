sub g { my $n = shift; if ($n > 2) { print "g" } return $n + 1 } sub f { my $n = shift; print "f"; return g($n) * 2 } print f(1), " ", f(5), "\n";
