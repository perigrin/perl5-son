sub f { my $n = shift; my $z = 0; foreach my $i (1, 2) { $z = $z + $n } print $z; return 0 }  my $v1 = 0; foreach my $i1 (1, 2) { $v1 = $v1 + $i1 } print $v1; f(2); f(1); print "\n";
