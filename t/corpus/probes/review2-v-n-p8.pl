sub f { my $n = shift; foreach my $i (1, 2) { print $i } return $n }
my $t = 0; $t = $t + f(4) + f(5); print " ", $t, "\n";
