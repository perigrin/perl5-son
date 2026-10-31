my @a = (1, 2); foreach my $x (1, 2) { $a[1] = $x; if ($x > 1) { $a[0] = 9 } print $a[0], $a[1] } print "\n";
