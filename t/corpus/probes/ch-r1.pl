sub id { my ($r) = @_; $r } sub w { my ($x) = @_; my $y = id($x); ref($y) } print w({}), w([]), w(\1), "\n";
