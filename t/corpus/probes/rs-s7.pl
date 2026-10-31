sub ld { "l" . $_[0] } my $s = 5; ld($s); $s =~ s/5/7/; print $s + 1, "\n";
