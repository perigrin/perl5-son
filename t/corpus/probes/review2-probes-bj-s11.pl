my $s = 0; foreach my $x (1, 2) { foreach my $y (1, 2) { print $y } $s = $s + 1; foreach my $z (1) { print $z } $s = $s * 2 } print "$s\n";
