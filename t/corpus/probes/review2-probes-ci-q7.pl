sub f { if ($_[0]) { print "x\n" } return 1 }
sub g { return 5 + f(1) }
print g(), "\n";
