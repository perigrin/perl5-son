my @a = (1, 2); my $r = \@a; sub f { my $x = shift; $x->[0] = 9; return 0 } my $before = $a[0]; f($r); print "$before $a[0]\n";
