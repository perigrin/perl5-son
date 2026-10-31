sub ld { "l" . $_[0] } my @a = (1, 2); for my $x (@a) { $x = $x * 2; print ld($x) } print " @a\n";
