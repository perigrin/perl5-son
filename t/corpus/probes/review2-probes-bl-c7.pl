sub f { my $n = shift; foreach my $i (1, 2) { print $i } return $n } my $s = 0; foreach my $k (1, 2) { $s = $s + $k } print f($s), "\n";
