sub f { my $n = shift; if ($n > 1) { print "b" } return $n } my $x = 5; if ($x > 2) { print f(3) } else { print f(0) } print "\n";
