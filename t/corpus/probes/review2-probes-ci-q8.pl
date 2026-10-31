sub f { if ($_[0]) { print "x\n" } return 1 }
sub g { f(1); return 5 }
print g(), "\n";
