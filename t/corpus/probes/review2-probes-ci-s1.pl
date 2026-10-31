sub g { my $m = shift; my $q = shift; return $m * 2 + $q }
sub f { my $n = shift; if ($n > 1) { print "big\n" } return $n + 1 }
print f(2), "\n";
print g(3, 1), "\n";
