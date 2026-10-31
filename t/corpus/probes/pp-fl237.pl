sub f { my ($h) = @_; my %p = %$h; for my $k (sort keys %p) { my $v = $p{$k}; $h->{$k} = $v + 10; print "$v $p{$k};" } return "" } print f({a=>1, b=>2}), "\n";
