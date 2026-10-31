sub g { die "bad $_[0]\n" if $_[0] % 2; $_[0] } my @e; for my $s (1 .. 4) { eval { g($s) }; push @e, $@ if $@ } print scalar(@e), " $e[0]";
