sub f { my $n = shift; if ($n > 1) { print "B" } return $n }
foreach my $i (1 .. 3) { print f($i) } print "\n";
