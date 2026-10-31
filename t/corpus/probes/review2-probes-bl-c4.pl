sub g { my $n = shift; my $s = 0; foreach my $i (1, 2) { $s = $s + $n } return $s } sub f { my $n = shift; if ($n > 1) { print "f" } return g($n) + 1 } print f(1), " ", f(3), "\n";
