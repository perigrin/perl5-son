sub bump { $_[0] = $_[0] + 1 } sub f { for my $x (@_) { bump($x) } return 1 } my $v = 1; f($v); print "$v\n";
