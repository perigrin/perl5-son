sub f { my $n = shift; if ($n > 1) { print "F" } return 0 } sub g { my $n = shift; return $n } my $x = g(5) + 1; f(1); print "$x\n";
