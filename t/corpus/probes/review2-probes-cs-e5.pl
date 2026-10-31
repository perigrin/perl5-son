sub f { my $n = shift; if ($n) { print "t" } else { print "f" } return 0 } "abc" =~ /(b)/; f($1); print "\n";
