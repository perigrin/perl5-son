sub f { my $n = shift; my $s = ""; for my $i (1..$n) { $s = $s . $i } return $s } my $s = "Q"; print f(3), $s, "\n";
