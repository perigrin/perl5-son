sub w { $_[0][$_[1]] = "z"; 1 } my @a = qw(a b c); w(\@a, 1); print "@a\n";
