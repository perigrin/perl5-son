sub f { $_[0] = 9; return scalar(@_) } my $v = 1; f($v); print "$v\n";
