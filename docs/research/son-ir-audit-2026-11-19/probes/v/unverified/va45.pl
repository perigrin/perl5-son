my @a = (1,2,3); for (@a) { local $_ = 9; } print "@a\n";
