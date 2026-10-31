foreach my $x (1, 2, 3) { foreach my $y (1, 2) { next if $y == 1; print $y } next if $x == 2; print "|" } print "\n";
