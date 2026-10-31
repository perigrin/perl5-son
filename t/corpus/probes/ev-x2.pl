sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my $t = 0; for my $s (1 .. 4) { $t += eval { g($s) } // 100 } print "$t\n";
