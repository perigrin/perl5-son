sub f { my $n = shift; if ($n > 1) { print "b" } print "c"; return $n } my $c = 3; if ($c > 1) { print f($c) } else { print "e" } print "\n";
