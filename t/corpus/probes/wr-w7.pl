sub ld { $_[0] } my $s = "abc"; print ld($s); substr($s, 0, 1) = "z"; print ld($s), "\n";
