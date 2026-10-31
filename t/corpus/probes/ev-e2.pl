sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { my $c; eval { $c = g($s); 1 } or $c = "x"; push @o, $c } print "@o\n";
