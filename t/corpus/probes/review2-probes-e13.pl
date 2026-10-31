sub f { my $n = shift; my $y = 0; if ($n > 0) { $y = 1 } elsif ($n < 0) { $y = 2 } return $y } print f(1), f(-1), f(0), "\n";
