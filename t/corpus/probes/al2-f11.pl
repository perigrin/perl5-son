sub ld { "l" . $_[0] } my $x = 1; my $r = \$x; $$r = 4; print ld($x), "\n";
