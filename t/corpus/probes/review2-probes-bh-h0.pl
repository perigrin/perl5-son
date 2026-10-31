sub f { my $n = shift; my $z = 0; foreach my $i (1, 2) { $z = $z + $n } print $z; return 0 }  f(2); f(1); print "\n";
