sub f { my $n = shift; if ($n > 1) { print "b" } return $n * 2 } for my $i (1..3) { print f($i), "," } print "\n";
