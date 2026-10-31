sub h { my $k = shift; print "h"; return $k } sub f { my $n = shift; if ($n > 1) { print "b" } return $n + 10 } print h(1) + f(2), "\n";
