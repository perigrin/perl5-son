sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (1 .. 4) { eval { push @o, g($s) }; push @o, "E" if $@ } print "@o\n";
