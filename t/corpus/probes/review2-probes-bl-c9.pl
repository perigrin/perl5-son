sub f { my $n = shift; foreach my $i (1, 2) { print $i } return $n } my $x = f(4); $x = $x + f(1); print "$x\n";
