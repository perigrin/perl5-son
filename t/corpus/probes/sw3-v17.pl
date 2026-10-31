my @a = (1, 2, 3); my @b = map { $_ * 2 } grep { $_ != 2 } @a; print "@b\n";
