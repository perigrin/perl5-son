sub g { my $k = shift; print "g$k"; return 1 } sub f { my $n = shift; if ($n > 1) { print "b" } return $n } my $a = f(2); my $b = g(7); print "|$a$b\n";
