my @q = (1 .. 5); my @e = grep { $_ % 2 == 0 } @q; my @m = map { $_ + 1 } @e; print "@m\n";
