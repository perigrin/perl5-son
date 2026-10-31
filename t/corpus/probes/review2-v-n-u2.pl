sub g { return $_[0] * 2 }
sub f { return g($_[0]) }
print f(3), "\n";
