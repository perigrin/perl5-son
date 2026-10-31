sub ld { "l" . $_[0] } my $s; ld($s); $s = "zz"; $s =~ s/z/y/; print ld($s), "\n";
