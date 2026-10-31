sub g { my @r = (0); for my $i (1 .. 3) { push @r, $i } return scalar(@r) } print g(), g(), "\n";
