sub ld { "l" . ($_[0] // "n") } for my $i (1 .. 3) { my $v; $v = $i if $i > 1; print ld($v) } print "\n";
