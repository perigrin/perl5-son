sub f { if ($_[0] > 1) { print "b" } return $_[0] } foreach my $i (1, 2, 3) { print f($i), "|" } print "\n";
