sub g { my $m = shift; return $m * 2 }
sub f { my $n = shift; if ($n > 1) { print "big\n" } return $n + 1 }
print f(2), "\n";
print g(3), "\n";
