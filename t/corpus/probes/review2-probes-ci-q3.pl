sub f { if ($_[0]) { print "x\n" } return 1 }
sub g { return $_[0] + f(1) }
print g(5), "\n";
