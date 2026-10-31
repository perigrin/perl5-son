my @o; my $i = 0; while ($i < 5) { $i++; if ($i == 3) { push @o, "t"; next } push @o, $i } print "@o\n";
