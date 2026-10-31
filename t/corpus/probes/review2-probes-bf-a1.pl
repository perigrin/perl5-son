sub f { my $n = shift; my $y = $n + 1; if ($n > 1) { $y = $y * 3 } return $y } my $v1 = 100; print $v1; print "|", f(2), "|", f(1), "\n";
