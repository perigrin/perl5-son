sub f { my $n = shift; my $s = 0; for my $i (1..$n) { $s = $s + $i } return $s }  my $v1 = 0; foreach my $i1 (1, 2) { $v1 = $v1 + $i1 } print $v1; print "|", f(3), "|", f(4), "\n";
