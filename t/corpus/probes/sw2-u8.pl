my %h = (x => [1, 2], y => [3]); my $n = 0; for my $k (sort keys %h) { $n += scalar @{ $h{$k} } } print "$n\n";
