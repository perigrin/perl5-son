my @a = (1, 2); my $c = 1; if ($c) { $a[1] = 5; foreach my $y (1, 2) { $a[0] = $y } print $a[0], $a[1] } print "\n";
