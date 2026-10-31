my @a = (1, 2); for my $x (@a) { push @a, 3 if $x == 1; $x = $x * 10 } print "@a\n";
