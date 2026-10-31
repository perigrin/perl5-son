my @a = (1, 2, 3); my @g = grep { $_++ } @a[0, 1]; print "@a|@g\n";
