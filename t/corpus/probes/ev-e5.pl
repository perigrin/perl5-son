use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; $_[0] * 2 } my $c; try { $c = g(2) } catch ($e) { $c = "x" } print "$c\n";
