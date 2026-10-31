sub f { my $n = shift; if ($n > 1) { print "b" } return $n * 2 } my $s = 0; foreach my $i (1,2,3) { my $t = f($i); print $t } print "\n";
