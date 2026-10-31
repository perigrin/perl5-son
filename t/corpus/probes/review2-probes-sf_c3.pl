sub f { my $n = shift; if ($n > 1) { print "F" } return 0 } sub g { return 5 } my $x = g() + 1; f(1); print "$x\n";
