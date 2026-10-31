sub ld { "l" . $_[0] } sub g { my $t = shift; my $r = ld($t); $t = $t * 10; return $r . ld($t) } print g(2), g(3), "\n";
