sub ld { $_[0] } my $s = "abc"; print ld($s); undef $s; print ld($s), "\n";
