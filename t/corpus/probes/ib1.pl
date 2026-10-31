sub f { my $n = 0; eval { $n = 1; die "d\n" if $_[0] }; return $n }
print f(1), f(0), "\n";
