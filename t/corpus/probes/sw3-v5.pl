my @w = qw(pear apple fig); my @s = sort { length($a) <=> length($b) or $a cmp $b } @w; print "@s\n";
