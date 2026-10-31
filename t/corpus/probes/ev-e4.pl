use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my @o; for my $s (3) { } my $s = 3; my $c; try { $c = g($s) } catch ($e) { $c = "x" } push @o, $c; print "@o\n";
