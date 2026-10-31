sub g { die "no\n" if $_[0] == 2; $_[0] } my $c = 0; eval { $c = g(1) + 1 }; print "$c\n";
