sub f { my ($n) = @_; if ($n > 1) { print "b" } return $n } foreach my $i (1, 2, 3) { print f($i), "|" } print "\n";
