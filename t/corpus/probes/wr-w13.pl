sub ld { $_[0] } my $s = "abc"; print ld($s); local $_ = 1; $s = $_; print ld($s), "\n";
