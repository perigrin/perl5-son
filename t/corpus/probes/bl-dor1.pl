sub f { my ($n) = @_; my $i = $n->{in} // []; return scalar(@$i) } print f({ in => [1, 2] }), f({}), "\n";
