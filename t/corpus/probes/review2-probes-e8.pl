sub f { my $n = shift; if ($n) { print "x" } return 1 } my $c = 1; if ($c) { f(1); print "|" } else { f(0) } print "\n";
