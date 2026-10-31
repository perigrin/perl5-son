my $c = 0; for my $i (1 .. 3) { for my $j (1 .. 3) { next if $i == $j; $c++ } } print "$c\n";
