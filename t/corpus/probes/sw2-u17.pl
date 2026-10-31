my $n = 0; for my $i (1 .. 10) { last if $i > 4; next if $i % 2; $n += $i } print "$n\n";
