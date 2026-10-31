sub ld { return defined $_[0] ? "d" : "u" } my $x; print ld($x); $x = 0; print ld($x), "\n";
