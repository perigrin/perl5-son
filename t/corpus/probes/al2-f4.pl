sub ld { "l" . $_[0] } my $s = "a"; $s .= "b"; print ld($s); $s .= "c"; print ld($s), "\n";
