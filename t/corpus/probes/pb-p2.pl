my @o; for (my $i = 0; $i < 5; $i += 2) { if ($i == 2) { $i--; next } push @o, $i } print "@o\n";
