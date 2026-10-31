sub f { my $n = scalar(@_); return $n > 1 ? "many" : "one" } print f(1), f(1, 2), "\n";
