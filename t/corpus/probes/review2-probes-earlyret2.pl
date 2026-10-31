sub f { my $n = shift; if ($n > 1) { print "b"; return 1 } print "s"; return 0 } print f(1), f(2), "\n";
