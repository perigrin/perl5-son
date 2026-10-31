sub f { my $n = shift; if ($n > 1) { print "big\n" } return 0 }
foreach my $i (1..3) { f($i) }
