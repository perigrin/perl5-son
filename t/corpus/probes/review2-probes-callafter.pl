sub f { my $n = shift; if ($n) { print "t" } return 0 } my $a = 1; f($a); $a = 0; f($a); print "\n";
