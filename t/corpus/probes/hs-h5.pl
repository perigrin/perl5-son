my %h; for my $i (1 .. 6) { $h{"k$i"} = $i * 2 } print $h{k1} + $h{k6}, " ", scalar(keys %h), "\n";
