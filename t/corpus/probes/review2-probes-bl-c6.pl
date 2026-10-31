sub f { my $n = shift; my $r = "s"; if ($n > 1) { $r = "b" } return $r } print f(2), f(1), "\n";
