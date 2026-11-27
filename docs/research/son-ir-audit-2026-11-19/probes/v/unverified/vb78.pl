my @r; OUT: for my $i (1..3) { for my $j (1..3) { next OUT if $j > 1; push @r, \$i } } print join(",", map { $$_ } @r), "\n";
