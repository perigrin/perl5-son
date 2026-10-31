 my $v1 = 100; print $v1; my $v2 = 200; print $v2; my $v3 = 300; print $v3; sub f { my $n = shift; my $s = 0; for my $i (1..$n) { $s = $s + $i } return $s } print "|", f(3), "\n";
