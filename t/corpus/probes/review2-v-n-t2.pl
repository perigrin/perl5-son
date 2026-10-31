sub g { return $_[0] * 2 }
sub f { print "F"; return g($_[0] + 1) }
print f(1), " ", f(3), "\n";
