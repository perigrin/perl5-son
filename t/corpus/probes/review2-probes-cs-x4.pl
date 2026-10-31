my @a = (3, 4); sub f { my $n = shift; my @l = (1, 2); if ($n > 1) { $l[0] = $n } return $l[0] } print $a[1], f($a[0]), $a[0], "\n";
