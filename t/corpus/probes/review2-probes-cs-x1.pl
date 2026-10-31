sub f { my $x = shift; my $v = $x->[0]; $x->[0] = 9; return $v + $x->[0] } print f([1, 2]), "\n";
