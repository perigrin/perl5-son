my $r = [1, 2]; sub f { my $x = shift; if ($x->[1] > 1) { $x->[0] = 9 } return 0 } my $b = $r->[0]; f($r); print "$b ", $r->[0], "\n";
