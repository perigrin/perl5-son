sub cnt { my $c = 0; $c++ for grep { $_ > 1 } @_; $c } print cnt(1, 2, 3), "\n";
