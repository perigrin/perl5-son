sub f { my $n = shift; foreach my $j (1 .. $n) { print "x" } return $n }
foreach my $i (1 .. 2) { foreach my $k (1..2) { print f($i) } print "|" } print "\n";
