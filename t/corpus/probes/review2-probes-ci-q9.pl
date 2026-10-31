sub f { print "x\n"; return 1 }
sub g { return 5 + f() }
print g(), "\n";
