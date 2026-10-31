my $s = "aaa"; my $c = 0; $c += ($s =~ tr/a//) for 1 .. 2; print "$c $s\n";
