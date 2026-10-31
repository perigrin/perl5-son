my @a = (1 .. 5); my @r; while (my $x = shift @a) { next if $x == 2; last if $x == 4; push @r, $x } print "@r|@a\n";
