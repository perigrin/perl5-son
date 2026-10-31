sub f { my $n = shift; for my $i (1..5) { last if $i > $n; print $i } return 0 } for my $j (1,2) { f($j); print "|" } print "\n";
