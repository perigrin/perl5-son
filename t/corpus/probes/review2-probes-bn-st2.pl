sub h { my $k = shift; print "h"; return $k } sub f { my $n = shift; if ($n > 1) { print "b" } return $n + 10 } my $a = h(1); my $b = f(2); print "$a $b\n";
