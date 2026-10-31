sub ld { "l" . $_[0] } my $s = "abc"; my $n = ($s =~ s/b/X/); print ld($s), " $n\n";
