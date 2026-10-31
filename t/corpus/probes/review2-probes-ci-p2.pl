sub g { return $_[0] * 2 }
sub f { if ($_[0] > 1) { print "big\n" } return $_[0] + 1 }
print g(3), "\n";
print f(5), "\n";
