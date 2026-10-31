sub f { my $n = shift; my @l = (1,2); push @l, $n; return scalar(@l) } my @m = (5,6,7,8); print f(3), " ", scalar(@m), "\n";
