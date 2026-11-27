my @a = (1, 2); for (@a) { $_ = "x$_" for my @c = @a; } print "@a\n";
