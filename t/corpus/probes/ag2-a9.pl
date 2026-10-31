sub g { return scalar(@_) } sub f { return g(1, 2) . scalar(@_) } print f(9), "\n";
