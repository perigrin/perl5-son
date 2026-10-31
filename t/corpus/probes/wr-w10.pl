sub ld { $_[0] } my $s = "abc"; print ld($s); $s ||= 5; print ld($s), "\n";
