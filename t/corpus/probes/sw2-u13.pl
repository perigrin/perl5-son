my @a = (1, 2, 3, 4); my @b = @a[1 .. 2]; $b[0] = 9; print "@a|@b\n";
