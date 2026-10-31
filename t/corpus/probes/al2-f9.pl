sub ld { "l" . $_[0] } my $x = 1; my $y = ld($x) . ld($x + 1); print "$y\n";
