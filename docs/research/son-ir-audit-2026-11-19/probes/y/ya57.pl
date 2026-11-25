my @a=(1,2); sub f { my $n=scalar @_; shift @a; "$n@_" } print f(@a), "\n";
