sub f { my $n = scalar(@_); my $r = \$_[0]; $$r = 5; return $n } my $v = 1; my $k = f($v); print "$v $k\n";
