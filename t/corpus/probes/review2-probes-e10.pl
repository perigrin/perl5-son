sub f { my $n = shift; if ($n) { print "x" } return 1 } my $v = 0; foreach my $i (1,2) { $v = $v + f($i) } print "$v\n";
