sub ld { "l" . $_[0] } my $n = 0; for my $i (1 .. 3) { $n = $n + $i; print ld($n) } print " $n\n";
