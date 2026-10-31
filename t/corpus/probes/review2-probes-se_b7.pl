sub f { my $n = shift; if ($n > 1) { print "F" } return $n } sub g { my $n = shift; print "G"; return $n } my $a = f(2); my $b = g(3); print "$a$b\n";
