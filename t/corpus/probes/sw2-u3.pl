my @a = (3, 1, 2); my @s = sort { $a <=> $b } @a; for my $i (0 .. $#s) { $s[$i] *= 2 if $i != 1 } print "@s|@a\n";
