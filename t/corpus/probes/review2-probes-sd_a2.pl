sub f { if ($_[0] > 1) { print "b" } return 1 } for my $i (1..3) { print f($i) } print "\n";
