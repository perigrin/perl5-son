for my $i (1 .. 2) { *f = sub { $i } } print f(), "\n";
