my $n = 0; my @o; for my $x (1 .. 5) { if ($x == 3) { $n = $x * 10; last } push @o, $x } print "$n @o\n";
