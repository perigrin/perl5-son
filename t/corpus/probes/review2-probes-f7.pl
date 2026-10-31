sub f { my $n = shift; foreach my $i (1..$n) { return $i if $i == 2 } return 0 } print f(4), "\n";
