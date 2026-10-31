sub f { my $n = shift; if ($n > 1) { print "b" } return $n * 2 } foreach my $i (1,2,3) { print f($i) } print "\n";
