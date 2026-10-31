my @a = (3, 4); sub f { my $n = shift; my @l = (1, 2); $l[0] = $n; return $l[0] + $l[1] } print f($a[0]), " ", $a[0], "\n";
