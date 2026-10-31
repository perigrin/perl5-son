my $s = ""; foreach my $x (1, 2) { foreach my $y ("a") { $s = $s . $y } $s = $s . "|" } print "$s\n";
