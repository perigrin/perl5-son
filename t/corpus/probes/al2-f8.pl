sub ld { "l" . ($_[0] // "u") } my $x; print ld($x); $x = 1.5; print ld($x); $x = "s"; print ld($x), "\n";
