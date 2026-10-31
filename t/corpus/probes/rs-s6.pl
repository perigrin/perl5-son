sub ld { "l" . $_[0] } my $s = "abc"; ld($s); my $n = 1; $n = $n + 0; if ($n) { print ld($s); $s =~ s/a/Q/ } print ld($s), "\n";
