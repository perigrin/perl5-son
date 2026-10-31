use v5.36;
sub g ($m) { return $m * 2 }
sub f ($n) { if ($n > 1) { print "big\n" } return $n + 1 }
print g(3), "\n";
print f(5), "\n";
