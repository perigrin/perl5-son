sub ld { "l" . $_[0] } my $s = "abc"; $s =~ s/a/1/; $s =~ s/b/2/; print ld($s), " $s\n";
