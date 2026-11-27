my @r; for my $i (1..3) { for ($i) { $_ *= 2 } push @r, \$i } print join(",", map { $$_ } @r), "\n";
