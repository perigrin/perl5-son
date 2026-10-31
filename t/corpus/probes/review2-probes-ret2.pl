sub f { my $n = shift; for my $i (1..3) { return $i if $i == $n } return 0 } print f(2), f(9), "\n"; print "end\n";
