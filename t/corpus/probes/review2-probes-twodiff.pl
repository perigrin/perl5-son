sub f { my $n = shift; my $y = 0; if ($n > 2) { $y = $n * 2 } else { $y = $n } return $y } print f(1) + f(5), "\n";
