sub f { my $n = shift; for my $i (1..$n) { print $i } return $n } my $x = 2; if ($x) { f($x) } else { f(1) } print "\n";
