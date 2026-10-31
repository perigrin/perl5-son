my @a = qw(x y z); my @g = grep { s/x/q/ } @a[0, 1]; print "@a|@g\n";
