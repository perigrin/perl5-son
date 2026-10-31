sub f { my $n = shift; if ($n > 1) { print "b" } return $n } for my $i (1..3) { f($i) } print "\n";
