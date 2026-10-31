use v5.36;
sub f ($n) { if ($n > 1) { print "big\n" } return $n + 1 }
sub g ($m) { return $m * 2 }
print f(5), "\n";
print g(3), "\n";
