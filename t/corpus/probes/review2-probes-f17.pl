sub f { my $n = shift; if ($n) { print "x" } return 1 } print f(1) + f(0) + f(1), "\n";
