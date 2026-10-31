my @a = (1, 2); sub f { my $n = shift; if ($n > 1) { print "b" } return $n } print f(2), $a[0], "\n";
