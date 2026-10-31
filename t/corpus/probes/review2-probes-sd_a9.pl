sub f { my $n = shift; if ($n) { print "t" } return 0 } my $i = 0; while ($i < 2) { f($i); $i++ } print "\n";
