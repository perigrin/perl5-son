sub f { my $n = shift; my $m = $n; if ($n > 1) { $m = $m + 10 } return $m } my $x = 2; my $y = $x; if ($x > 1) { $y = f($x) } print "$y ", f(1), "\n";
