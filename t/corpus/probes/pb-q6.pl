my @o; for my $x (1 .. 4) { if ($x == 2) { push @o, "x"; push @o, "y"; next } elsif ($x == 3) { next } push @o, $x } print "@o\n";
