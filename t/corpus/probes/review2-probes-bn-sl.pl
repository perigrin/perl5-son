sub h { my $k = shift; print "h"; return $k } sub f { my $n = shift; print "f"; return $n + 10 } print h(1) + f(2), "\n";
