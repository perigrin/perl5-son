sub add { my ($h) = @_; $h->{b} = 2; 2 } my %p = (a => 1); add(\%p); print exists $p{b} ? "y" : "n", $p{b}, "\n";
