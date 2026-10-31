sub ld { "l" . $_[0] } my $x = 1; if ($x) { my $x = 5; print ld($x) } print ld($x), "\n";
