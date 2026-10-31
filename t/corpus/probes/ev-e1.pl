sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { my $c = eval { g($s) }; push @o, $c // "x" } print "@o\n";
