no warnings; sub f { my $n = shift; if ($n == 2) { last } return 1 } foreach my $i (1,2,3) { f($i); print $i } print "\n";
