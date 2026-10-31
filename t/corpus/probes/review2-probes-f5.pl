sub f { my $n = shift; my $s = 0; foreach my $i (1..$n) { if ($i == 2) { next } $s = $s + $i } return $s } print f(4), "\n";
