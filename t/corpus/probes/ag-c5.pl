sub f { my @p = @_; push @p, 9; return "@p|@_" } print f(1, 2), "\n";
