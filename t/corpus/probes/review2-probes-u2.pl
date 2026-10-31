sub f { my $n = shift; my $y = $n; if ($n) { $y = 9 } return $y } if (f(1)) { print "t" } else { print "f" } print "\n";
