sub f { my $n = shift; my $y; if ($n) { $y = 5 } return defined $y ? $y : "u" } print f(1), f(0), "\n";
