my @r; for my $i (1..2) { push @r, \$i } print ${$r[0]}, "\n";
