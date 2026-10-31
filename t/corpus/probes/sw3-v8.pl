my @m = ([1, 2], [3, 4]); my $t = 0; for my $r (@m) { for my $c (@$r) { next if $c == 3; $t += $c } } print "$t\n";
