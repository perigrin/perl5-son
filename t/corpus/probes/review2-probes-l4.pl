sub f { my $n = shift; my $y = $n; foreach my $i (1, 2) { $y = $y + $i } return $y } my $a = 100; print f(1) + $a, "\n";
