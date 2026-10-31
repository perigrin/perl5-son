sub f { my $n = shift; if ($n > 1) { print "big "; return 5 } print "small "; return 0 } print f(1), f(2), "\n";
