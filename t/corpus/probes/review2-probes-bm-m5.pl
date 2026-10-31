sub f { my $n = shift; if ($n > 1) { print "b" } return $n } sub h { my $n = shift; foreach my $i (1) { print "h" } return $n } print h(1) + f(2), "\n";
