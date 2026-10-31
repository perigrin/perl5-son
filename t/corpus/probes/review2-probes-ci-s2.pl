sub f { my $n = shift; if ($n > 1) { print "big\n" } return $n + 1 }
sub g { my $m = shift; my $q = shift; return f($m) + $q }
print g(3, 1), "\n";
