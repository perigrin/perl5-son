my $r = [1, 2]; sub f { my $x = shift; my $v = $x->[0]; $x->[0] = $v + 5; return $v } print f($r), " ", f($r), " ", $r->[0], "\n";
