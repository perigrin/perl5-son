sub f { my $n = shift; if ($n > 1) { print "b" } return $n } my $t = f(2); if ($t > 1) { print "big" } else { print "small" } print "\n";
