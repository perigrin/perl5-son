sub f { my $n = shift; my $s = 0; foreach my $i (1, 2) { $s = $s + $n } return $s } foreach my $k (1, 2) { print f($k), "|" } print "\n";
