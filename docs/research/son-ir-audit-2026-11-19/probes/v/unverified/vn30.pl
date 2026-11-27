my @r; for my $i (1..2) { $i *= 10; for my $j (1..2) { push @r, \$i } } print join(",", map { $$_ } @r), "\n";
