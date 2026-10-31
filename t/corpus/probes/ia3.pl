sub f { my $n = 0; eval { for my $x (@_) { $n = $x; die "d\n" if $x eq "b" } }; return $n }
print f("a","b","c"), "\n";
