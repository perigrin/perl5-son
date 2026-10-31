sub f { my $n = shift; if ($n) { print "x" } return 1 } foreach my $i (1,0,1) { f($i) } print "\n";
