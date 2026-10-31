sub f { print "x\n"; return 1 }
sub g { return $_[0] + f(1) }
print g(5), "\n";
