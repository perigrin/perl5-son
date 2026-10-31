sub ld { "l" . $_[0] } my $x = 1; print ld($x); { my $x = 2; print ld($x); } print ld($x), "\n";
