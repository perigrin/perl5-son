my @a = (1, 2); for my $x (1 .. 2) { my $t = $a[0]; $a[1] = $t + $x } print "@a\n";
