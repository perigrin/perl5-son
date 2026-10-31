my @o; for (my $i = 0; $i < 6; $i++) { if ($i == 1) { push @o, "s"; $i += 2; next } push @o, $i } print "@o\n";
