sub f { my $n = shift; my $y = 1; if ($n) { $y = 2 } return $y } my $y = 5; my $n = 7; print f(0), f(1), $y, $n, "\n";
