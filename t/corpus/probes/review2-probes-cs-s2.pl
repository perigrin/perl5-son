sub f { if ($_[0] > 1) { print "F" } return $_[0] + 1 }
sub g { if ($_[0] > 1) { print "G" } return $_[0] * 2 }
print f(1), " ", g(5), " ", f(3), "\n";
